//
//  Shaders.metal
//  MTLPaint
//
//  Migrated to Metal by OOPer in cooperation with shlab.jp, on 2019/4/26.
//  See point.vsh and point.fsh in the original project.
//

#include <metal_stdlib>
using namespace metal;

typedef struct
{
    float4 position  [[position]];
    half4  color;
    float  pointSize [[point_size]];
} FragColor;

vertex FragColor PointVertex(const device float2 *inVertex   [[ buffer(0) ]],
                             constant float4x4&  MVP         [[ buffer(1) ]],
                             constant float&     pointSize   [[ buffer(2) ]],
                             constant float4&    vertexColor [[ buffer(3) ]],
                             uint                vid         [[ vertex_id ]]) {
    FragColor out;

    out.position = MVP * float4(inVertex[vid], 0, 1);
    out.color = half4(vertexColor);
    out.pointSize = pointSize;
    
    return out;
}

fragment half4 PointFragment(FragColor        in         [[ stage_in ]],
                             texture2d<half>  texture    [[ texture(0)  ]],
                             sampler          sam        [[ sampler(0)  ]],
                             float2           pointCoord [[ point_coord ]]) {
    half4 c = texture.sample(sam, pointCoord);
    return c * in.color;
}
