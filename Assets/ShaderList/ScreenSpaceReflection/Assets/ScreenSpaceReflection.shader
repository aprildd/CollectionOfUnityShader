﻿Shader "Hidden/ScreenSpaceReflection"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		Cull Off 
		ZWrite Off
		ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 csRay : TEXCOORD1;
			};

			sampler2D _MainTex;
			float4 _MainTex_TexelSize;
			sampler2D _CameraGBufferTexture1;
			sampler2D _CameraGBufferTexture2;
			sampler2D _CameraDepthTexture;
			sampler2D _BackfaceTex;
			float4x4 _Projection;
			float4x4 _WorldToView;

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				//转换到NDC坐标
				float4 cameraRay = float4(v.uv * 2.0 - 1.0, 1.0, 1.0);
				//转换到投影空间
				cameraRay = mul(unity_CameraInvProjection, cameraRay);
				//得到到远剪裁面的射线
				o.csRay = cameraRay / cameraRay.w;
				return o;
			}

			#include "ScreenSpaceRaytrace.cginc"

#define SCREEN_EDGE_MASK 0.9

			//求Alpha
			float alphaCalc(float3 rayDirection, float2 hitPixel, float marchPercent, float hitZ) {
				float res = 1;
				//saturate;限制在0到1之间
				res *= saturate(-5 * (rayDirection.z - 0.2));

				float2 screenPCurrent = 2 * (hitPixel - 0.5);
				res *= 1 - max(
					(clamp(abs(screenPCurrent.x), SCREEN_EDGE_MASK, 1.0) - SCREEN_EDGE_MASK) / (1 - SCREEN_EDGE_MASK),
					(clamp(abs(screenPCurrent.y), SCREEN_EDGE_MASK, 1.0) - SCREEN_EDGE_MASK) / (1 - SCREEN_EDGE_MASK)
				);
				res *= 1 - marchPercent;
				res *= 1 - (-(hitZ - 0.2) * _ProjectionParams.w);
				return res;
			}

			fixed4 frag (v2f i) : SV_Target
			{
				//得到深度
				float decodedDepth = Linear01Depth(tex2D(_CameraDepthTexture, i.uv).r);
				//射线*深度值，还原像素的观察空间坐标
				float3 csRayOrigin = decodedDepth * i.csRay;
				//得到反射位置世界坐标系法线
				float3 wsNormal = tex2D(_CameraGBufferTexture2, i.uv).rgb * 2.0 - 1.0;
				//观察坐标系法线
				float3 csNormal = normalize(mul((float3x3)_WorldToView, wsNormal));
				float2 hitPixel;
				float3 debugCol;

				half3 reflection = 0;
				float alpha = 0;
				//得到反射方向射线
				float3 reflectionDir = normalize(reflect(csRayOrigin, csNormal));
				
				float2 uv2 = i.uv * _MainTex_TexelSize.zw;
				float c = (uv2.x + uv2.y) * 0.25;

				//fmod(x,y):x/y求余
				float jitter = fmod(c,1.0);

				float marchPercent;//命中率
				float hitZ;//命中点的深度值
				float rayBump = max(-0.018*csRayOrigin.z, 0.001);

				//检测相交，返回命中点的屏幕坐标hitpixel
				if (traceRay(csRayOrigin + csNormal * rayBump,reflectionDir,jitter,_MainTex_TexelSize,hitPixel,marchPercent,hitZ)) {
					alpha = alphaCalc(reflectionDir, hitPixel, marchPercent,hitZ);
				}
				//反射color
				reflection = tex2D(_MainTex, hitPixel);	
				//原color与反射color混合
				return tex2D(_MainTex, i.uv) + half4(reflection,1) * alpha;
			}
			ENDCG
		}
	}
}
