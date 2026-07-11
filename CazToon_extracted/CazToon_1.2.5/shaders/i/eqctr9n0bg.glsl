#ifdef WATER_DEBUG_COLORS_ENABLED
color.rgb = vec3(0.0, 1.0, 1.0);
color.a = 0.35;
#else
color.rgb = applyLightingWithShadow(color.rgb, sunAngle, skylight, bl_water, 0.0, shadow, worldPos.y);
#endif
