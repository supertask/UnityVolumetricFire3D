#include "./rgb_to_cmyk.hlsl"

#define RAY_STEPS_TO_FLUID 64
#define RAY_STEPS_TO_LIGHT 6

struct VertexInput {
    float4 positionOS : POSITION; //vertex position in object space
    float3 normal : NORMAL;
    float4 texcoord : TEXCOORD0;
};

struct v2f 
{
    float4 positionCS : SV_POSITION;
    float3 positionWS : TEXCOORD0;
    float3 screenPos : TEXCOORD1;
    float3 viewVector : TEXCOORD2;
};

struct Ray {
    float3 origin;
    float3 dir;
};

struct BoundingBox {
    float3 Min;
    float3 Max;
};

//
// Fire & smoke settings
//
//sampler2D _FireGradient;
//sampler2D _SmokeGradient;

Texture2D<float4> FireGradient;
Texture2D<float4> SmokeGradient;
SamplerState samplerFireGradient;
SamplerState samplerSmokeGradient;

float _SmokeAbsorption, _FireAbsorption; //absorption = 吸収
uniform float3 _BoundingPosition, _BoundingScale, _Size;
StructuredBuffer<float> _Density, _Reaction, _Temperature;
float3 boundsMax;
float3 boundsMin;
//float4 _SmokeColor;
//float4 _FireColor;
float _FireIntensity;


//Camera background texture
#if defined(UNIT_RP__URP)
    uniform sampler2D _CameraOpaqueTexture;
#elif defined(UNIT_RP__BUILT_IN_RP)
    uniform sampler2D _GrabTexture;
#elif defined(UNIT_RP__HDRP)
    //Nothing
#endif 

// Marching settings

// Shape settings
float4 _PhaseParams;
float _DensityOffset;
float _ReactionOffset;

// Light settings
float _LightAbsorptionTowardSun;
float _LightAbsorptionThroughCloud;
float _DarknessThreshold;
float4 _LightColor0;
float4 _SkyColor;

float2 _FireTemperatureRange;
float2 _SmokeDensityRange;


// Henyey-Greenstein(散乱位相関数モデル)
// https://www.astro.umd.edu/~jph/HG_note.pdf
float hg(float a, float g) {
    float g2 = g*g;
    return (1-g2) / (4*3.1415*pow(1+g2-2*g*(a), 1.5));
}

//https://www.cps-jp.org/~mosir/pub/2013/2013-11-28/01_satou/pub-web/20131128_satou_01.pdf 
float phase(float a) {
    float blend = .5;
    float hgBlend = hg(a,_PhaseParams.x) * (1-blend) + hg(a,-_PhaseParams.y) * blend;
    return _PhaseParams.z + hgBlend*_PhaseParams.w;
}

float remap(float v, float minOld, float maxOld, float minNew, float maxNew) {
    return minNew + (v-minOld) * (maxNew - minNew) / (maxOld-minOld);
}

float2 squareUV(float2 uv) {
    float width = _ScreenParams.x;
    float height =_ScreenParams.y;
    //float minDim = min(width, height);
    float scale = 1000;
    float x = uv.x * width;
    float y = uv.y * height;
    return float2 (x/scale, y/scale);
}

float3 blendLikePaint(float3 rbgL, float3 rgbR)     {
    return CMYKtoRGB(RGBtoCMYK(rbgL) + RGBtoCMYK(rgbR));
}

float2 rayBoundsDistance(Ray ray, BoundingBox boundingBox)
{
    float3 inverseRayDir = 1.0 / ray.dir;
    float3 tbot = inverseRayDir * (boundingBox.Min-ray.origin);
    float3 ttop = inverseRayDir * (boundingBox.Max-ray.origin);
    float3 tmin = min(ttop, tbot);
    float3 tmax = max(ttop, tbot);
    float2 t = max(tmin.xx, tmin.yz);
    float distanceIntersectedToNearBounds = max(t.x, t.y);
    t = min(tmax.xx, tmax.yz);
    float distanceIntersectedToFarBounds = min(t.x, t.y);

    return float2(distanceIntersectedToNearBounds, distanceIntersectedToFarBounds);
}

//find intersection points of a ray with a box
bool intersectBox(Ray ray, BoundingBox boundingBox, out float t0, out float t1)
{
    float3 invR = 1.0 / ray.dir;
    float3 tbot = invR * (boundingBox.Min-ray.origin);
    float3 ttop = invR * (boundingBox.Max-ray.origin);
    float3 tmin = min(ttop, tbot);
    float3 tmax = max(ttop, tbot);
    float2 t = max(tmin.xx, tmin.yz);
    t0 = max(t.x, t.y);
    t = min(tmax.xx, tmax.yz);
    t1 = min(t.x, t.y);
    return t0 <= t1;
}

float SampleBilinear(StructuredBuffer<float> buffer, float3 uvw, float3 size)
{
    uvw = saturate(uvw);
    uvw = uvw * (size-1.0);

    int x = uvw.x;
    int y = uvw.y;
    int z = uvw.z;
    
    int X = size.x;
    int XY = size.x*size.y;
    
    float fx = uvw.x-x;
    float fy = uvw.y-y;
    float fz = uvw.z-z;
    
    int xp1 = min(_Size.x-1, x+1);
    int yp1 = min(_Size.y-1, y+1);
    int zp1 = min(_Size.z-1, z+1);
    
    float x0 = buffer[x+y*X+z*XY] * (1.0f-fx) + buffer[xp1+y*X+z*XY] * fx;
    float x1 = buffer[x+y*X+zp1*XY] * (1.0f-fx) + buffer[xp1+y*X+zp1*XY] * fx;
    
    float x2 = buffer[x+yp1*X+z*XY] * (1.0f-fx) + buffer[xp1+yp1*X+z*XY] * fx;
    float x3 = buffer[x+yp1*X+zp1*XY] * (1.0f-fx) + buffer[xp1+yp1*X+zp1*XY] * fx;
    
    float z0 = x0 * (1.0f-fz) + x1 * fz;
    float z1 = x2 * (1.0f-fz) + x3 * fz;
    
    return z0 * (1.0f-fy) + z1 * fy;
    
}

// Convert World position to UVW position
float3 convertFromWorldPosToUVW(float3 rayWorldPos) {
    float3 rayUVWPos = (rayWorldPos - _BoundingPosition + 0.5*_BoundingScale)/_BoundingScale;
    return rayUVWPos;
}

float samplePhysicalQuantity(StructuredBuffer<float> buffer,
        float3 rayWorldPos, BoundingBox boundingBox, float physicalQuantityOffset) {
    float3 rayUVWPos = convertFromWorldPosToUVW(rayWorldPos);
    float sampledPhysicalQuantity = SampleBilinear(buffer, rayUVWPos, _Size);
    float physicalQuantity = physicalQuantityOffset * sampledPhysicalQuantity;
    return physicalQuantity;
}

// 
// Ref. Sebastian Lague, Clouds, https://github.com/SebLague/Clouds
float lightmarch(StructuredBuffer<float> buffer, Ray rayTowardsLight,
        BoundingBox boundingBox, float physicalQuantityOffset) {

    float dstInsideBox = rayBoundsDistance(rayTowardsLight, boundingBox).y; //Confirmed!!!
    
    float stepSize = dstInsideBox/RAY_STEPS_TO_LIGHT;
    float totalPhysicalQuantity = 0;

    float3 lightRayPos = rayTowardsLight.origin;
    for (int step = 0; step < RAY_STEPS_TO_LIGHT; step ++) {
        lightRayPos += rayTowardsLight.dir * stepSize;
        float physicalQuantity = samplePhysicalQuantity(buffer, lightRayPos, boundingBox, physicalQuantityOffset);
        totalPhysicalQuantity += max(0, physicalQuantity * stepSize);
    }
    float transmittance = exp(-totalPhysicalQuantity * _LightAbsorptionTowardSun);
    return _DarknessThreshold + transmittance * (1-_DarknessThreshold);
}

float4 volumetricRayMarching(
    float3 positionWS,
    float2 screenUV,
    float3 mainCameraPos,
    float3 mainLightPosition,
    float3 mainLightColor) {

    Ray ray;
    ray.origin = mainCameraPos;
    ray.dir = normalize(positionWS - mainCameraPos);
    
    BoundingBox boundingBox;
    boundingBox.Min = float3(-0.5,-0.5,-0.5)*_BoundingScale + _BoundingPosition;
    boundingBox.Max = float3(0.5,0.5,0.5)*_BoundingScale + _BoundingPosition;

    //figure out where ray from eye hit front of cube
    float2 rayToContainerInfo = rayBoundsDistance(ray, boundingBox);
    float dstToBox = rayToContainerInfo.x;
    float dstInsideBox = rayToContainerInfo.y;

    //if eye is in cube then start ray at eye
    if (dstToBox < 0.0) dstToBox = 0.0;

    float3 entryPoint = ray.origin + ray.dir * dstToBox;
    float3 exitPoint = ray.origin + ray.dir * dstInsideBox;

    // Phase function makes clouds brighter around sun
    //float cosAngle = dot(ray.dir, _WorldSpaceLightPos0.xyz);
    float cosAngle = dot(ray.dir, mainLightPosition.xyz);
    float phaseVal = phase(cosAngle);

    float3 rayPos = entryPoint;
    float stepSize = distance(exitPoint, entryPoint)/float(RAY_STEPS_TO_FLUID); //This is problem of while loop
    //float stepSize = 0.05;
    //float3 ds = normalize(exitPoint-entryPoint) * stepSize;
    //float dstLimit = min(depth-dstToBox, dstInsideBox);

    float sunLightEneryOnSmoke = 0.0;
    float sunLightEnergyOnFire = 0.0;
    float fireLightEnergyOnSmoke = 0.0;
    float fireTransmittance = 1.0, smokeTransmittanceForSun = 1.0, smokeTransmittanceForFireLight = 1.0;
    float dstLimit = dstInsideBox - dstToBox;
    float dstTravelled = 0.0;
    //float dstTravelled = randomOffset;

    float normalizedFireTemperature = 1.0;
    float normalizedSmokeTemperature = 1.0;

    //while (dstTravelled < dstLimit) {
    //for(int i=0; i < RAY_STEPS_TO_FLUID; i++, rayPos += ds) {
    for(int i=0; i < RAY_STEPS_TO_FLUID; i++, dstTravelled += stepSize) {
        rayPos = entryPoint + ray.dir * dstTravelled;

        float density = samplePhysicalQuantity(_Density, rayPos, boundingBox, _DensityOffset);
        float reaction = samplePhysicalQuantity(_Reaction, rayPos, boundingBox, _ReactionOffset);

        if (density > 0) {
            Ray rayTowardsSunLight;
            rayTowardsSunLight.origin = rayPos;
            rayTowardsSunLight.dir = mainLightPosition;

            float sunLightTransmittanceOnSmoke = lightmarch(_Density, rayTowardsSunLight, boundingBox, _DensityOffset);
            sunLightEneryOnSmoke += density * stepSize * smokeTransmittanceForSun * sunLightTransmittanceOnSmoke * phaseVal;
            smokeTransmittanceForSun *= exp(-density * stepSize * _LightAbsorptionThroughCloud);
            //if not very dense, most light makes it through
            //if very dense, not much light makes it through
        }
        if (reaction > 0) {
            Ray rayTowardsSunLight;
            rayTowardsSunLight.origin = rayPos;
            rayTowardsSunLight.dir = mainLightPosition;

            float sunLightTransmittanceOnFire = lightmarch(_Reaction, rayTowardsSunLight, boundingBox, _DensityOffset);
            sunLightEnergyOnFire += reaction * stepSize * fireTransmittance * sunLightTransmittanceOnFire * phaseVal;
            fireTransmittance *= exp(-reaction * stepSize * _LightAbsorptionThroughCloud );
        }

        // Temperature(0 ~ 1) for binding temperature with color
        // Ref. https://github.com/Scrawk/GPU-GEMS-3D-Fluid-Simulation/blob/master/Assets/FluidSim3D/Shaders/FireRayCast.shader#L154-L156
        normalizedSmokeTemperature *= 1.0-saturate(density * stepSize * 1.0); //TODO(Tasuku): 0.5 to variable
        normalizedFireTemperature *= 1.0-saturate(reaction * stepSize * 1.0); //TODO(Tasuku): 0.5 to variable
        if (normalizedSmokeTemperature <= 0.01 && normalizedFireTemperature <= 0.01) break;
        if (smokeTransmittanceForSun <= 0.01 && fireTransmittance <= 0.01) break;

    }

    //Debug
    //float fireMap = 1.0-fireTransmittance;
    //return float4(fireMap, fireMap, fireMap, 1.0);
    //float smokeMap = 1.0-smokeTransmittanceForSun;
    //return float4(smokeMap, smokeMap, smokeMap, 1.0);


    //float4 fireCol = _FireColor;
    float4 fireCol = FireGradient.SampleLevel(samplerFireGradient, float2(normalizedFireTemperature, 0), 0);

    //Multiplying emission by density(1 - smokeTransmittanceForSun) makes better fire.
    //Ref. https://youtu.be/Hy4R5Vf-dVM?t=1079
    fireCol = fireCol * _FireIntensity * sunLightEnergyOnFire * (1 - smokeTransmittanceForSun); 

    float4 smoke = SmokeGradient.SampleLevel(samplerSmokeGradient, float2(normalizedSmokeTemperature, 0), 0);
    float4 smokeCol = float4(sunLightEneryOnSmoke * blendLikePaint(mainLightColor.rgb, smoke.rgb), 1.0 - smokeTransmittanceForSun);

    // Load scene color
    #if defined(UNIT_RP__BUILT_IN_RP)
        float4 sceneColor = tex2D(_GrabTexture, screenUV);
    #elif defined(UNIT_RP__URP)
        float4 sceneColor = tex2D(_CameraOpaqueTexture, screenUV);
    #endif

    return lerp(smokeCol, sceneColor, smokeTransmittanceForSun) + fireCol;

}

