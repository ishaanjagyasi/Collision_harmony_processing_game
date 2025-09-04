/**
 * Chord Collisions — Pad Edition (Processing + OscP5)
 *
 * Controls
 *   Arrow keys       : move pad
 *   W / S            : current pitch class up/down  [shows big popup]
 *   A / D            : pad length - / +
 *   Mouse click      : spawn ball at mouse (current pitch class)
 *   X                : delete ALL balls of current pitch class
 *   Backspace/Delete : delete nearest ball to mouse
 *   V                : toggle pad orientation (H/V)
 *   C                : clear all balls
 *
 * OSC
 *   /collision    i i s f f f
 *   /blob/update  i i f f f f f
 */

import oscP5.*;
import netP5.*;
import java.util.*;

OscP5 osc;
NetAddress maxAddr;

final int   PORT_OUT   = 7400;
final String HOST      = "127.0.0.1";

final float RADIUS     = 22f;
final float DRAG       = 0.9985f;
final float MAX_SPEED  = 7.0f;

final float REST_BB    = 0.98f;
final float MU_BB      = 0.06f;
final float REST_PAD   = 1.04f;
final float MU_PAD     = 0.05f;
final float REST_WALL  = 0.98f;

final float PAD_THICK  = 18f;
final float PAD_SPEED  = 7.0f;

// ---- Pitch popup ----
final int   POPUP_MS   = 2000;     // 2s fade
String popupText = "";
int    popupStartMs = -999999;

// ---- Fonts (crisp text) ----
PFont hudFont;     // small UI
PFont popupFont;   // big center popup

ArrayList<Blob> blobs = new ArrayList<>();
int nextId = 0;

Pad pad;
int currentPC = 0;

boolean K_LEFT=false, K_RIGHT=false, K_UP=false, K_DOWN=false;

// consonance weights (folded to 0..6)
float[] intervalWeights = new float[]{1.00,0.10,0.25,0.20,0.85,0.80,0.05,0.80,0.20,0.25,0.15,0.20};

void setup() {
  size(1100, 700, P2D);
  smooth(8);
  textMode(SHAPE);                       // vector text (crisp at any size)
  hudFont   = createFont("SansSerif", 14, true);
  popupFont = createFont("SansSerif.bold", 200, true);

  osc = new OscP5(this, 0);
  maxAddr = new NetAddress(HOST, PORT_OUT);

  pad = new Pad(width*0.5f, height*0.65f, 300, false);
  surface.setTitle("Chord Collisions — Pad Edition v0.4.3");
}

void draw() {
  background(12);

  // --- Pad update ---
  pad.beginFrame();
  float dx = (K_RIGHT?1:0) - (K_LEFT?1:0);
  float dy = (K_DOWN?1:0)  - (K_UP?1:0);
  pad.moveBy(dx * PAD_SPEED, dy * PAD_SPEED);
  pad.constrainToBounds();
  pad.endFrame();

  // --- Blob integration + pad collisions ---
  for (Blob b : blobs) {
    b.integrate();
    b.wallBounce();
    collidePadCircle(pad, b);
    sendBlobUpdate(b);
  }

  // --- Ball↔Ball collisions ---
  collideBalls();

  // --- Render world ---
  for (Blob b : blobs) b.render();
  pad.render();

  // --- HUD (explicit small font/size every frame) ---
  drawHUD();

  // --- Pitch popup (on top) ---
  drawPitchPopup();
}

void drawHUD() {
  textFont(hudFont);
  textSize(14);
  fill(255);
  textAlign(LEFT, TOP);
  text("Pad Edition v0.4.3", 12, 10);
  text("Blobs: " + blobs.size(), 12, 28);
  text("Current note: " + noteName(currentPC) + "  [" + currentPC + "]", 12, 46);
  text("Pad: " + (pad.vertical ? "Vertical" : "Horizontal") + "  len=" + int(pad.length), 12, 64);
  text("Arrows move | W/S note | A/D length | Click spawn | X delete pitch-class | ⌫ delete nearest | V toggle | C clear", 12, 82);
  text("OSC -> " + HOST + ":" + PORT_OUT, 12, 100);
}

// =================== Input ===================

void mousePressed() {
  if (mouseButton == LEFT) {
    float ang = random(TWO_PI);
    float spd = random(1.2f, 2.2f);
    blobs.add(new Blob(nextId++, mouseX, mouseY, cos(ang)*spd, sin(ang)*spd, currentPC, colorFromPitch(currentPC)));
  }
}

void keyPressed() {
  if (keyCode == LEFT)  K_LEFT = true;
  if (keyCode == RIGHT) K_RIGHT = true;
  if (keyCode == UP)    K_UP = true;
  if (keyCode == DOWN)  K_DOWN = true;

  if (key == 'w' || key == 'W') { currentPC = (currentPC + 1) % 12; triggerPitchPopup(currentPC); }
  else if (key == 's' || key == 'S') { currentPC = (currentPC + 11) % 12; triggerPitchPopup(currentPC); }

  else if (key == 'a' || key == 'A') pad.length = max(80, pad.length - 20);
  else if (key == 'd' || key == 'D') pad.length = min(680, pad.length + 20);

  else if (key == 'x' || key == 'X') removePitchClass(currentPC);
  else if (key == BACKSPACE || key == DELETE) deleteNearestBlob();
  else if (key == 'c' || key == 'C') { blobs.clear(); nextId = 0; }
  else if (key == 'v' || key == 'V') pad.vertical = !pad.vertical;
}

void keyReleased() {
  if (keyCode == LEFT)  K_LEFT = false;
  if (keyCode == RIGHT) K_RIGHT = false;
  if (keyCode == UP)    K_UP = false;
  if (keyCode == DOWN)  K_DOWN = false;
}

// =================== Physics ===================

void collideBalls() {
  for (int i = 0; i < blobs.size(); i++) {
    for (int j = i+1; j < blobs.size(); j++) {
      Blob A = blobs.get(i), B = blobs.get(j);
      float dx = B.x - A.x, dy = B.y - A.y;
      float dist2 = dx*dx + dy*dy;
      float minDist = RADIUS*2f;

      if (dist2 < minDist*minDist) {
        float dist = max(1e-6f, sqrt(dist2));
        float nx = dx/dist, ny = dy/dist;
        float penetration = (minDist - dist);

        // positional correction
        float percent = 0.8f, slop = 0.01f;
        float corrMag = max(penetration - slop, 0) * percent * 0.5f;
        A.x -= nx * corrMag; A.y -= ny * corrMag;
        B.x += nx * corrMag; B.y += ny * corrMag;

        // relative velocity
        float rvx = B.vx - A.vx, rvy = B.vy - A.vy;
        float velN = rvx*nx + rvy*ny;
        if (velN > 0) continue;

        // normal impulse
        float e = REST_BB;
        float impN = -(1+e) * velN / 2.0f;
        float jx = impN * nx, jy = impN * ny;
        A.vx -= jx; A.vy -= jy;
        B.vx += jx; B.vy += jy;

        // tangential friction
        float tx = rvx - velN*nx, ty = rvy - velN*ny;
        float tl = sqrt(tx*tx + ty*ty);
        if (tl > 1e-6f) { tx /= tl; ty /= tl; } else { tx = -ny; ty = nx; }
        float velT = rvx*tx + rvy*ty;
        float jt = -velT / 2.0f;
        float maxFric = MU_BB * abs(impN);
        jt = constrain(jt, -maxFric, maxFric);
        float jtx = jt * tx, jty = jt * ty;
        A.vx -= jtx; A.vy -= jty;
        B.vx += jtx; B.vy += jty;

        // sonify
        int pcA = A.pc, pcB = B.pc;
        float score = intervalConsonance(pcA, pcB);
        String label = intervalLabel(pcA, pcB);
        float cx = (A.x + B.x) * 0.5f, cy = (A.y + B.y) * 0.5f;
        flash(cx, cy, score);
        sendCollision(pcA, pcB, label, score, cx, cy);
      }
    }
  }
}

void collidePadCircle(Pad P, Blob B) {
  float hw = P.vertical ? PAD_THICK*0.5f : P.length*0.5f;
  float hh = P.vertical ? P.length*0.5f  : PAD_THICK*0.5f;

  float cx = constrain(B.x, P.x - hw, P.x + hw);
  float cy = constrain(B.y, P.y - hh, P.y + hh);

  float dx = B.x - cx, dy = B.y - cy;
  float d2 = dx*dx + dy*dy;

  if (d2 <= RADIUS*RADIUS) {
    float d = max(1e-6f, sqrt(d2));
    float nx = dx/d, ny = dy/d;

    // position correction
    float penetration = (RADIUS - d);
    float percent = 0.9f, slop = 0.01f;
    float corr = max(penetration - slop, 0) * percent;
    B.x += nx * corr; B.y += ny * corr;

    // relative velocity vs pad
    float rvx = B.vx - P.vx, rvy = B.vy - P.vy;
    float velN = rvx*nx + rvy*ny;
    if (velN > 0) return;

    // normal impulse (pad infinite mass)
    float e = REST_PAD;
    float impN = -(1+e) * velN;
    B.vx += impN * nx; B.vy += impN * ny;

    // tangential friction
    float tx = rvx - velN*nx, ty = rvy - velN*ny;
    float tl = sqrt(tx*tx + ty*ty);
    if (tl > 1e-6f) { tx /= tl; ty /= tl; } else { tx = -ny; ty = nx; }
    float velT = rvx*tx + rvy*ty;
    float jt = -velT;
    float maxFric = MU_PAD * abs(impN);
    jt = constrain(jt, -maxFric, maxFric);
    B.vx += jt * tx; B.vy += jt * ty;
  }
}

// =================== Popup Overlay ===================

void triggerPitchPopup(int pc) {
  popupText = noteName(pc);
  popupStartMs = millis();
}

void drawPitchPopup() {
  int elapsed = millis() - popupStartMs;
  if (elapsed < 0 || elapsed > POPUP_MS) return;

  float t = elapsed / (float)POPUP_MS;       // 0..1
  float alpha = 255 * (1.0 - t);             // fade out
  // size eases from slightly bigger to normal
  float base = min(width, height) * 0.22;
  float sizeNow = base * (1.08 - 0.08*t);

  textFont(popupFont);
  textSize(sizeNow);
  textAlign(CENTER, CENTER);

  // shadow
  fill(0, (int)(alpha * 0.6));
  text(popupText, width/2f + 3, height/2f + 5);

  // main
  fill(255, (int)alpha);
  text(popupText, width/2f, height/2f);
}

// =================== Helpers ===================

void deleteNearestBlob() {
  if (blobs.isEmpty()) return;
  int idx = -1;
  float best = 1e9;
  for (int i = 0; i < blobs.size(); i++) {
    Blob b = blobs.get(i);
    float d2 = sq(b.x - mouseX) + sq(b.y - mouseY);
    if (d2 < best) { best = d2; idx = i; }
  }
  if (idx >= 0) blobs.remove(idx);
}

void removePitchClass(int pc) {
  pc = ((pc%12)+12)%12;
  for (int i = blobs.size()-1; i >= 0; i--) if (blobs.get(i).pc == pc) blobs.remove(i);
}

float intervalConsonance(int pcA, int pcB) {
  int iv = Math.floorMod(pcB - pcA, 12);
  iv = min(iv, 12 - iv);
  return intervalWeights[iv];
}

String intervalLabel(int pcA, int pcB) {
  int iv = Math.floorMod(pcB - pcA, 12);
  int ivInv = min(iv, 12 - iv);
  String[] names = {"P1","m2","M2","m3","M3","P4","TT","P5","m6","M6","m7","M7"};
  return noteName(pcA) + "–" + names[ivInv];
}

void sendCollision(int pcA, int pcB, String label, float score, float cx, float cy) {
  OscMessage m = new OscMessage("/collision");
  m.add(pcA); m.add(pcB); m.add(label); m.add(score); m.add(cx); m.add(cy);
  osc.send(m, maxAddr);
}

void sendBlobUpdate(Blob b) {
  OscMessage m = new OscMessage("/blob/update");
  float spd = sqrt(b.vx*b.vx + b.vy*b.vy);
  m.add(b.id); m.add(b.pc);
  m.add(b.x);  m.add(b.y);
  m.add(b.vx); m.add(b.vy);
  m.add(spd);
  osc.send(m, maxAddr);
}

void flash(float x, float y, float score) {
  float s = map(constrain(score, 0, 1.0f), 0, 1.0f, 28, 120);
  noFill();
  stroke(score >= 0.6f ? color(90, 220, 160) : color(230, 90, 110));
  strokeWeight(3);
  circle(x, y, s);
  strokeWeight(1);
}

String noteName(int pc) {
  String[] names = {"C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"};
  return names[Math.floorMod(pc,12)];
}

int colorFromPitch(int pc) {
  colorMode(HSB, 360, 100, 100);
  float h = (pc / 12.0f) * 360.0f;
  int c = color(h, 75, 95);
  colorMode(RGB, 255);
  return c;
}

// =================== Classes ===================

class Blob {
  int id, pc, col;
  float x, y, vx, vy;

  Blob(int id, float x, float y, float vx, float vy, int pc, int col) {
    this.id=id; this.x=x; this.y=y; this.vx=vx; this.vy=vy; this.pc=pc; this.col=col;
  }

  void integrate() {
    vx *= DRAG; vy *= DRAG;
    x += vx; y += vy;

    float s2 = vx*vx + vy*vy;
    if (s2 > MAX_SPEED*MAX_SPEED) {
      float s = sqrt(s2);
      vx = vx/s*MAX_SPEED;
      vy = vy/s*MAX_SPEED;
    }
  }

  void wallBounce() {
    if (x < RADIUS) { x = RADIUS; vx = abs(vx) * REST_WALL; }
    if (x > width - RADIUS) { x = width - RADIUS; vx = -abs(vx) * REST_WALL; }
    if (y < RADIUS) { y = RADIUS; vy = abs(vy) * REST_WALL; }
    if (y > height - RADIUS) { y = height - RADIUS; vy = -abs(vy) * REST_WALL; }
  }

  void render() {
    noStroke();
    fill(col);
    circle(x, y, RADIUS*2);

    textFont(hudFont);
    textSize(12);
    fill(0, 170);
    rectMode(CENTER);
    rect(x, y + RADIUS + 10, 32, 16, 3);
    fill(255);
    textAlign(CENTER, CENTER);
    text(noteName(pc), x, y + RADIUS + 10);
  }
}

class Pad {
  float x, y, length; boolean vertical;
  float lastX, lastY, vx, vy;

  Pad(float x, float y, float length, boolean vertical) {
    this.x=x; this.y=y; this.length=length; this.vertical=vertical;
    this.lastX=x; this.lastY=y; this.vx=0; this.vy=0;
  }

  void beginFrame() { lastX = x; lastY = y; }
  void endFrame() { vx = x - lastX; vy = y - lastY; }

  void moveBy(float dx, float dy) { x += dx; y += dy; }

  void constrainToBounds() {
    float hw = vertical ? PAD_THICK*0.5f : length*0.5f;
    float hh = vertical ? length*0.5f    : PAD_THICK*0.5f;
    x = constrain(x, hw, width - hw);
    y = constrain(y, hh, height - hh);
  }

  void render() {
    noStroke();
    fill(255, 200);
    rectMode(CENTER);
    if (vertical) rect(x, y, PAD_THICK, length, 6);
    else          rect(x, y, length, PAD_THICK, 6);
  }
}
