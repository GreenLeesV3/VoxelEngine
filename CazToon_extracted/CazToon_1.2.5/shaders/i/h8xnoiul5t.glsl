#ifdef WATER_DEBUG_COLORS_ENABLED
color.rgb = vec3(0.5, 0.5, 0.5);
color.a = 0.35;
#else
color.rgb = waterLitColor(color.rgb, sunAngle, skylight, bl_water);
#endif
