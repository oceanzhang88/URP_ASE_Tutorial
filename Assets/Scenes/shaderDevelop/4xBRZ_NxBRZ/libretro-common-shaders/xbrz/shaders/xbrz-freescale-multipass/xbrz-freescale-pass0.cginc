/* COMPATIBILITY 
   - HLSL compilers
   - Cg   compilers
*/

// xBRZ freescale
// based on :

// 4xBRZ shader - Copyright (C) 2014-2016 DeSmuME team
//
// This file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 2 of the License, or
// (at your option) any later version.
//
// This file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with the this software.  If not, see <http://www.gnu.org/licenses/>.


/*
   Hyllian's xBR-vertex code and texel mapping
   
   Copyright (C) 2011/2016 Hyllian - sergiogdb@gmail.com
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is 
   furnished to do so, subject to the following conditions:
   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.
*/ 

static const int BLEND_NONE = 0;
static const int BLEND_NORMAL = 1;
static const int BLEND_DOMINANT = 2;
static const float LUMINANCE_WEIGHT = 1.0;
static const float EQUAL_COLOR_TOLERANCE = 0.1176470588235294; // 30.0/255.0
static const float STEEP_DIRECTION_THRESHOLD = 2.2;
static const float DOMINANT_DIRECTION_THRESHOLD = 3.6;

void main_vertex
(
	float4 position	: POSITION,
	float4 color	: COLOR,
	float2 texCoord : TEXCOORD0,

    uniform float4x4 modelViewProj,

	out float4 oPosition : POSITION,
	out float4 oColor    : COLOR,
	out float2 otexCoord : TEXCOORD
)
{
	oPosition = mul(modelViewProj, position);
	oColor = color;
	otexCoord = texCoord;
}

struct output 
{
  float4 color    : COLOR;
};

struct input
{
  float2 video_size;
  float2 texture_size;
  float2 output_size;
  float  frame_count;
  float  frame_direction;
  float frame_rotation;
};

float DistYCbCr(float3 pixA, float3 pixB)
{
  const float3 w = float3(0.2627, 0.6780, 0.0593);
  const float scaleB = 0.5 / (1.0 - w.b);
  const float scaleR = 0.5 / (1.0 - w.r);
  float3 diff = pixA - pixB;
  float Y = dot(diff.rgb, w);
  float Cb = scaleB * (diff.b - Y);
  float Cr = scaleR * (diff.r - Y);

  return sqrt(((LUMINANCE_WEIGHT * Y) * (LUMINANCE_WEIGHT * Y)) + (Cb * Cb) + (Cr * Cr));
}

bool IsPixEqual(const float3 pixA, const float3 pixB)
{
  return (DistYCbCr(pixA, pixB) < EQUAL_COLOR_TOLERANCE);
}

float get_left_ratio(float2 center, float2 origin, float2 direction, float2 scale)
{
  float2 P0 = center - origin;
  float2 proj = direction * (dot(P0, direction) / dot(direction, direction));
  float2 distv = P0 - proj;
  float2 orth = float2(-direction.y, direction.x);
  float side = sign(dot(P0, orth));
  float v = side * length(distv * scale);

//  return step(0, v);
  return smoothstep(-sqrt(2.0)/2.0, sqrt(2.0)/2.0, v);
}

//#define eq(a,b)  (a == b)
bool eq(float3 a, float3 b)
{
   return ((a.x==b.x)&&(a.y==b.y)&&(a.z==b.z));
}
//#define neq(a,b) (a != b)
bool neq(float3 a, float3 b)
{
   return !((a.x==b.x)&&(a.y==b.y)&&(a.z==b.z));
}

#define P(x,y) tex2D(Source, coord + (1.0 / texture_size.xy) * float2(x, y)).rgb

float4 xbrz_freescale(float2 texture_size, float2 video_size, float2 output_size, float2 texcoord, sampler2D Source)
{
  //---------------------------------------
  // Input Pixel Mapping:  -|x|x|x|-
  //                       x|A|B|C|x
  //                       x|D|E|F|x
  //                       x|G|H|I|x
  //                       -|x|x|x|-

  float2 pos = frac(texcoord * texture_size.xy) - float2(0.5, 0.5);
  float2 coord = texcoord - pos * (1.0 / texture_size);

  float3 A = P(-1.,-1.);
  float3 B = P( 0.,-1.);
  float3 C = P( 1.,-1.);
  float3 D = P(-1., 0.);
  float3 E = P( 0., 0.);
  float3 F = P( 1., 0.);
  float3 G = P(-1., 1.);
  float3 H = P( 0., 1.);
  float3 I = P( 1., 1.);

  // blendResult Mapping: x|y|
  //                      w|z|
  int4 blendResult = int4(BLEND_NONE,BLEND_NONE,BLEND_NONE,BLEND_NONE);

  // Preprocess corners
  // Pixel Tap Mapping: -|-|-|-|-
  //                    -|-|B|C|-
  //                    -|D|E|F|x
  //                    -|G|H|I|x
  //                    -|-|x|x|-
  if (!((eq(E,F) && eq(H,I)) || (eq(E,H) && eq(F,I))))
  {
    float dist_H_F = DistYCbCr(G, E) + DistYCbCr(E, C) + DistYCbCr(P(0.,2.), I) + DistYCbCr(I, P(2.,0.)) + (4.0 * DistYCbCr(H, F));
    float dist_E_I = DistYCbCr(D, H) + DistYCbCr(H, P(1.,2.)) + DistYCbCr(B, F) + DistYCbCr(F, P(2.,1.)) + (4.0 * DistYCbCr(E, I));
    bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_H_F) < dist_E_I;
    blendResult.z = ((dist_H_F < dist_E_I) && neq(E,F) && neq(E,H)) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }


  // Pixel Tap Mapping: -|-|-|-|-
  //                    -|A|B|-|-
  //                    x|D|E|F|-
  //                    x|G|H|I|-
  //                    -|x|x|-|-
  if (!((eq(D,E) && eq(G,H)) || (eq(D,G) && eq(E,H))))
  {
    float dist_G_E = DistYCbCr(P(-2.,1.)  , D) + DistYCbCr(D, B) + DistYCbCr(P(-1.,2.), H) + DistYCbCr(H, F) + (4.0 * DistYCbCr(G, E));
    float dist_D_H = DistYCbCr(P(-2.,0.)  , G) + DistYCbCr(G, P(0.,2.)) + DistYCbCr(A, E) + DistYCbCr(E, I) + (4.0 * DistYCbCr(D, H));
    bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_D_H) < dist_G_E;
    blendResult.w = ((dist_G_E > dist_D_H) && neq(E,D) && neq(E,H)) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }

  // Pixel Tap Mapping: -|-|x|x|-
  //                    -|A|B|C|x
  //                    -|D|E|F|x
  //                    -|-|H|I|-
  //                    -|-|-|-|-
  if (!((eq(B,C) && eq(E,F)) || (eq(B,E) && eq(C,F))))
  {
    float dist_E_C = DistYCbCr(D, B) + DistYCbCr(B, P(1,-2)) + DistYCbCr(H, F) + DistYCbCr(F, P(2.,-1.)) + (4.0 * DistYCbCr(E, C));
    float dist_B_F = DistYCbCr(A, E) + DistYCbCr(E, I) + DistYCbCr(P(0.,-2.), C) + DistYCbCr(C, P(2.,0.)) + (4.0 * DistYCbCr(B, F));
    bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_B_F) < dist_E_C;
    blendResult.y = ((dist_E_C > dist_B_F) && neq(E,B) && neq(E,F)) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }

  // Pixel Tap Mapping: -|x|x|-|-
  //                    x|A|B|C|-
  //                    x|D|E|F|-
  //                    -|G|H|-|-
  //                    -|-|-|-|-
  if (!((eq(A,B) && eq(D,E)) || (eq(A,D) && eq(B,E))))
  {
    float dist_D_B = DistYCbCr(P(-2.,0.), A) + DistYCbCr(A, P(0.,-2.)) + DistYCbCr(G, E) + DistYCbCr(E, C) + (4.0 * DistYCbCr(D, B));
    float dist_A_E = DistYCbCr(P(-2.,-1.), D) + DistYCbCr(D, H) + DistYCbCr(P(-1.,-2.), B) + DistYCbCr(B, F) + (4.0 * DistYCbCr(A, E));
    bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_D_B) < dist_A_E;
    blendResult.x = ((dist_D_B < dist_A_E) && neq(E,D) && neq(E,B)) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }

  float4 FragColor = float4(blendResult);

  // Pixel Tap Mapping: -|-|-|-|-
  //                    -|-|B|C|-
  //                    -|D|E|F|x
  //                    -|G|H|I|x
  //                    -|-|x|x|-
  if(blendResult.z == BLEND_DOMINANT || (blendResult.z == BLEND_NORMAL &&
    !((blendResult.y != BLEND_NONE && !IsPixEqual(E, G)) || (blendResult.w != BLEND_NONE && !IsPixEqual(E, C)) ||
     (IsPixEqual(G, H) && IsPixEqual(H, I) && IsPixEqual(I, F) && IsPixEqual(F, C) && !IsPixEqual(E, I)))))
 {
   FragColor.z += 4.0;

   float dist_F_G = DistYCbCr(F, G);
   float dist_H_C = DistYCbCr(H, C);

   if((STEEP_DIRECTION_THRESHOLD * dist_F_G <= dist_H_C) && neq(E,G) && neq(D,G))
      FragColor.z += 16.0;

   if((STEEP_DIRECTION_THRESHOLD * dist_H_C <= dist_F_G) && neq(E,C) && neq(B,C))
      FragColor.z += 64.0;
 }

  // Pixel Tap Mapping: -|-|-|-|-
  //                    -|A|B|-|-
  //                    x|D|E|F|-
  //                    x|G|H|I|-
  //                    -|x|x|-|-
  if(blendResult.w == BLEND_DOMINANT || (blendResult.w == BLEND_NORMAL &&
      !((blendResult.z != BLEND_NONE && !IsPixEqual(E, A)) || (blendResult.x != BLEND_NONE && !IsPixEqual(E, I)) ||
       (IsPixEqual(A, D) && IsPixEqual(D, G) && IsPixEqual(G, H) && IsPixEqual(H, I) && !IsPixEqual(E, G)))))
 {
   FragColor.w += 4.0;

   float dist_H_A = DistYCbCr(H, A);
   float dist_D_I = DistYCbCr(D, I);

   if((STEEP_DIRECTION_THRESHOLD * dist_H_A <= dist_D_I) && neq(E,A) && neq(B,A))
      FragColor.w += 16.0;

   if((STEEP_DIRECTION_THRESHOLD * dist_D_I <= dist_H_A) && neq(E,I) && neq(F,I))
      FragColor.w += 64.0;
 }

  // Pixel Tap Mapping: -|-|x|x|-
  //                    -|A|B|C|x
  //                    -|D|E|F|x
  //                    -|-|H|I|-
  //                    -|-|-|-|-
  if(blendResult.y == BLEND_DOMINANT || (blendResult.y == BLEND_NORMAL &&
     !((blendResult.x != BLEND_NONE && !IsPixEqual(E, I)) || (blendResult.z != BLEND_NONE && !IsPixEqual(E, A)) ||
      (IsPixEqual(I, F) && IsPixEqual(F, C) && IsPixEqual(C, B) && IsPixEqual(B, A) && !IsPixEqual(E, C)))))
 {
   FragColor.y += 4.0;

   float dist_B_I = DistYCbCr(B, I);
   float dist_F_A = DistYCbCr(F, A);

   if((STEEP_DIRECTION_THRESHOLD * dist_B_I <= dist_F_A) && neq(E,I) && neq(H,I))
      FragColor.y += 16.0;

   if((STEEP_DIRECTION_THRESHOLD * dist_F_A <= dist_B_I) && neq(E,A) && neq(D,A))
      FragColor.y += 64.0;
 }

  // Pixel Tap Mapping: -|x|x|-|-
  //                    x|A|B|C|-
  //                    x|D|E|F|-
  //                    -|G|H|-|-
  //                    -|-|-|-|-
  if(blendResult.x == BLEND_DOMINANT || (blendResult.x == BLEND_NORMAL &&
   !((blendResult.w != BLEND_NONE && !IsPixEqual(E, C)) || (blendResult.y != BLEND_NONE && !IsPixEqual(E, G)) ||
     (IsPixEqual(C, B) && IsPixEqual(B, A) && IsPixEqual(A, D) && IsPixEqual(D, G) && !IsPixEqual(E, A)))))
 {
   FragColor.x += 4.0;

   float dist_D_C = DistYCbCr(D, C);
   float dist_B_G = DistYCbCr(B, G);

   if((STEEP_DIRECTION_THRESHOLD * dist_D_C <= dist_B_G) && neq(E,C) && neq(F,C))
      FragColor.x += 16.0;

   if((STEEP_DIRECTION_THRESHOLD * dist_B_G <= dist_D_C) && neq(E,G) && neq(H,G))
      FragColor.x += 64.0;
 }
   FragColor /= 255.0;
   return FragColor;
}

output main_fragment(float2 texCoord : TEXCOORD0, uniform sampler2D decal : TEXUNIT0, uniform input IN) 
{
   output OUT;
   OUT.color = xbrz_freescale(IN.texture_size, IN.video_size, IN.output_size, texCoord, decal);
   return OUT;
}