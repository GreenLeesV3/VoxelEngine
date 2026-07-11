#ifndef END_EVENT_GLSL
#define END_EVENT_GLSL

struct EndEvent {
float skyDarkness;
float vortexSpeedMult;
float vortexSizeMult;
float effectsFade;
float cloudSpeedMult;
float eyeOpen;
float bangFlash;
float bangProgress;
float terrainDarkness;
float fogDarkness;
float suctionWarp;
float vortexTime;
float cloudTime;
};

float eventSmooth(float t) {
return t * t * (3.0 - 2.0 * t);
}

EndEvent getEndEvent(float time) {
EndEvent e;
e.skyDarkness = 0.0;
e.vortexSpeedMult = 1.0;
e.vortexSizeMult = 1.0;
e.effectsFade = 1.0;
e.cloudSpeedMult = 1.0;
e.eyeOpen = 0.0;
e.bangFlash = 0.0;
e.bangProgress = -1.0;
e.terrainDarkness = 0.0;
e.fogDarkness = 0.0;
e.suctionWarp = 0.0;
e.vortexTime = time;
e.cloudTime = time;

float cycleTime = END_EVENT_CYCLE;

float p1Dur = 12.0;
float p2Dur = 10.0;
float p3Dur = END_EVENT_BLACKOUT;
float p4Dur = 4.0;
float p5Dur = 12.0;
float p6Dur = 10.0;

float eventDuration = p1Dur + p2Dur + p3Dur + p4Dur + p5Dur + p6Dur;
float eventStart = cycleTime - eventDuration;
float t = mod(time, cycleTime);

if (t < eventStart) return e;

float et = t - eventStart;

float p1End = p1Dur;
float p2End = p1End + p2Dur;
float p3End = p2End + p3Dur;
float p4End = p3End + p4Dur;
float p5End = p4End + p5Dur;

float p1FullInteg = p1Dur + 5.0 * p1Dur / 3.0;

float p2FullInteg = (6.0 + 12.0) * 0.5 * p2Dur;

float cp1FullInteg = p1Dur + 4.0 * p1Dur / 3.0;
float cp2FullInteg = (5.0 + 10.0) * 0.5 * p2Dur;

float integ = 0.0;
float cInteg = 0.0;

if (et < p1End) {
float p = et / p1Dur;
p = p * p;
e.vortexSpeedMult = mix(1.0, 6.0, p);
e.cloudSpeedMult = mix(1.0, 5.0, p);
e.vortexSizeMult = mix(1.0, 0.5, p);

integ = et + 5.0 * et * et * et / (3.0 * p1Dur * p1Dur);

cInteg = et + 4.0 * et * et * et / (3.0 * p1Dur * p1Dur);
}

else if (et < p2End) {
float p = (et - p1End) / p2Dur;
float ease = eventSmooth(p);
e.vortexSpeedMult = mix(6.0, 12.0, ease);
e.cloudSpeedMult = mix(5.0, 10.0, ease);
e.vortexSizeMult = mix(0.5, 0.0, ease);
e.skyDarkness = ease;
e.effectsFade = 1.0 - ease;
e.suctionWarp = ease;
e.terrainDarkness = ease;
e.fogDarkness = ease;

float p2Local = et - p1End;
float avgSpeed = mix(6.0, mix(6.0, 12.0, ease), 0.5);
integ = p1FullInteg + avgSpeed * p2Local;

float cAvgSpeed = mix(5.0, mix(5.0, 10.0, ease), 0.5);
cInteg = cp1FullInteg + cAvgSpeed * p2Local;
}

else if (et < p3End) {
e.skyDarkness = 1.0;
e.effectsFade = 0.0;
e.vortexSpeedMult = 0.0;
e.vortexSizeMult = 0.0;
e.cloudSpeedMult = 0.0;
e.suctionWarp = 1.0;
e.terrainDarkness = 1.0;
e.fogDarkness = 1.0;

float p3Local = et - p2End;
float p3Frac = p3Local / p3Dur;
float smoothP3 = eventSmooth(p3Frac);

float integ_fast = p1FullInteg + p2FullInteg;
float integ_real = (p1Dur + p2Dur) + p3Local;
integ = mix(integ_fast, integ_real, smoothP3);

float cInteg_fast = cp1FullInteg + cp2FullInteg;
cInteg = mix(cInteg_fast, integ_real, smoothP3);
}

else if (et < p4End) {
float p = (et - p3End) / p4Dur;
float bang = pow(p, 0.4);
float vortexGrow = p * p;
e.bangProgress = p;
e.bangFlash = max(1.0 - p * 4.0, 0.0);
e.bangFlash *= e.bangFlash;
e.skyDarkness = 1.0 - bang;
e.effectsFade = bang;
e.vortexSpeedMult = 1.0;
e.vortexSizeMult = vortexGrow;
e.cloudSpeedMult = mix(0.0, 1.0, bang);
e.suctionWarp = 1.0 - bang;
e.terrainDarkness = 1.0 - bang;
e.fogDarkness = 1.0 - bang;

integ = et;
cInteg = et;
}

else if (et < p5End) {
float p = (et - p4End) / p5Dur;

#ifdef END_EVENT_EYE_ENABLED
if (p < 0.20) {
e.eyeOpen = eventSmooth(p / 0.20);
} else if (p < 0.51) {
e.eyeOpen = 1.0;
} else if (p < 0.535) {
float blinkP = (p - 0.51) / 0.025;
e.eyeOpen = 1.0 - eventSmooth(blinkP);
} else if (p < 0.555) {
float blinkP = (p - 0.535) / 0.02;
e.eyeOpen = eventSmooth(blinkP);
} else if (p < 0.80) {
e.eyeOpen = 1.0;
} else {
float closeP = (p - 0.80) / 0.20;
e.eyeOpen = 1.0 - eventSmooth(closeP);
}
#endif

integ = et;
cInteg = et;
}

else {

integ = et;
cInteg = et;
}

e.vortexTime = (time - t) + eventStart + integ;
e.cloudTime = (time - t) + eventStart + cInteg;

return e;
}

float getEndEventTerrainDarkness(float time) {
float cycleTime = END_EVENT_CYCLE;
float p1End = 12.0;
float p2End = p1End + 10.0;
float p3End = p2End + END_EVENT_BLACKOUT;
float p4End = p3End + 4.0;
float eventDuration = p4End + 12.0 + 10.0;
float eventStart = cycleTime - eventDuration;
float t = mod(time, cycleTime);

if (t < eventStart) return 0.0;
float et = t - eventStart;

if (et >= p1End && et < p2End) {
float p = (et - p1End) / 10.0;
return eventSmooth(p);
}

if (et >= p2End && et < p3End) return 1.0;

if (et >= p3End && et < p4End) {
float p = (et - p3End) / 4.0;
return 1.0 - pow(p, 0.4);
}
return 0.0;
}

#endif
