#ifdef WATER_DEBUG_COLORS_ENABLED
color.rgb = vec3(1.0, 0.5, 0.0);
color.a = 0.35;
#else
color.rgb = waterLitColor(color.rgb, sunAngle, skylight);
#endif
