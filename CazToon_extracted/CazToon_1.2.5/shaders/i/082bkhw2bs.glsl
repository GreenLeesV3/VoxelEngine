#ifdef RENDER_SETUP
layout(r32ui) uniform writeonly uimage1D lpvBlockMaskImg;
#else
layout(r32ui) uniform readonly uimage1D lpvBlockMaskImg;
#endif
