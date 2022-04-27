Shader "Opal/ScreenSpace/Psycho"
{
    Properties
    {
        [Header(Saturation)]
        [Toggle(EXPENSIVE_LUMA)]
        _ExpensiveLuma ("Expensive Luma", int) = 1
        _Saturation ("Saturation", float) = 1.0

        [Header(Sharpness)]
        [Toggle(SHARPNESS_ENABLED)]
        _SharpnessEnabled ("Sharpness Enabled", int) = 1
        _Sharpness ("Sharpness", float) = 0.0
        _SharpnessRadius ("Sharpness Radius", float) = 0.0005

        [Header(Chromatic Aberration)]
        [Toggle(CHROMA_ENABLED)]
        _ChromaEnabled ("Chroma Enabled", int) = 1
        _ChromaRadius ("Chroma Radius", float) = 0.0001

        [Header(Tunnel Vision)]
        [Toggle(TUNNELVISION_ENABLED)]
        _TunnelVisionEnabled ("Tunnel Vision Enabled", int) = 1
        _TunnelVisionRadius ("Tunnel Vision Radius", float) = 1

        [Header(Color Shifting)]
        _RedRemap ("Red Remap", vector) = (1.0, 0.0, 0.0, 1.0)
        _GreenRemap ("Green Remap", vector) = (0.0, 1.0, 0.0, 1.0)
        _BlueRemap ("Blue Remap", vector) = (0.0, 0.0, 1.0, 1.0)

        [Header(Posterization)]
        _PosterizationBands ("Posterization Bands", float) = 10
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+100" }
        LOD 100
        ZWrite Off

        GrabPass {}
        Pass
        {
            Cull Front
            ZTest Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            #pragma shader_feature SHARPNESS_ENABLED
            #pragma shader_feature EXPENSIVE_LUMA
            #pragma shader_feature CHROMA_ENABLED
            #pragma shader_feature TUNNELVISION_ENABLED

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 screenCoords : TEXCOORD0;
                float3x3 remap : TEXCOORD1;

                UNITY_VERTEX_OUTPUT_STEREO 
            };

            UNITY_DECLARE_SCREENSPACE_TEXTURE(_GrabTexture);

            float _BlurSpeed;
            float _Saturation;
            float _Sharpness, _SharpnessRadius;
            float _TunnelVisionRadius;
            float _ChromaRadius;
            fixed3 _RedRemap, _GreenRemap, _BlueRemap;
            float _PosterizationBands;

            v2f vert (appdata v)
            {
                v2f o;
                
                UNITY_SETUP_INSTANCE_ID(v);
				UNITY_INITIALIZE_OUTPUT(v2f, o);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.screenCoords = ComputeGrabScreenPos(o.vertex);
                o.remap = float3x3(_RedRemap, _GreenRemap, _BlueRemap);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float2 uv = i.screenCoords.xy / i.screenCoords.w;

                //
                // Tunnel vision
                //
                float fade = 1;

                #ifdef TUNNELVISION_ENABLED
                float d = distance(uv, (0.5)) / _TunnelVisionRadius;
                fade = 1 - saturate(d);
                #endif

                //
                // Chroma
                // 
                #ifdef CHROMA_ENABLED
                float2 chromaUV = uv;
                //float2 offset = (chromaUV - (0.5).xx) * _ChromaRadius;
                float2 offset = float2(_ChromaRadius, 0);

                fixed3 c00 = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, chromaUV + offset).rgb * fade;
                fixed3 c01 = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, chromaUV).rgb * fade;
                fixed3 c02 = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, chromaUV - offset).rgb * fade;

                fixed3 cur = saturate(c00 * _RedRemap + c01 * _GreenRemap + c02 * _BlueRemap);
                #else                
                fixed3 cur = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv) * fade;
                #endif

                cur.rgb = saturate(mul(i.remap, cur.rgb));

                //
                // Sharpness
                // 
                #ifdef SHARPNESS_ENABLED
                float2 step = (_SharpnessRadius).xx;

                fixed3 l00 = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv + float2(-step.x, -step.y)).xyz * fade;
                fixed3 l01 = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv + float2(step.x, -step.y)).xyz * fade;
                fixed3 l02 = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv + float2(-step.x, step.y)).xyz * fade;
                fixed3 l03 = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv + float2(step.x, step.y)).xyz * fade;

                fixed3 around = mul(float3x3(_RedRemap, _GreenRemap, _BlueRemap), l00 + l01 + l02 + l03);
                around /= 4.0;

                cur = cur + (cur - around) * _Sharpness; 
                cur = saturate(cur);
                #endif

                //
                // Saturation
                //
                #ifndef EXPENSIVE_LUMA // Cheaper luma that doesn't require sqrt
                
                float avg = (0.2126 * cur.r + 0.7152 * cur.g + 0.0722 * cur.b);
                
                #else // More expensive but more accurate
                
                float avg = sqrt(0.299 * (cur.r * cur.r) + 0.587 * (cur.g * cur.g) + 0.114 * (cur.b * cur.b));
                
                #endif

                if (_Saturation > 1) {
                    cur.rgb += (cur - avg.rrr) * _Saturation;
                } else {
                    cur.rgb = lerp(avg.rrr, cur, saturate(_Saturation));
                }

                cur = saturate(cur); // Make sure we don't corrupt any frames

                //
                // Posterization
                //
                cur.rgb = lerp(cur.rgb, floor(cur * _PosterizationBands) / _PosterizationBands, saturate(_PosterizationBands / 2));

                return fixed4(cur, 1);
            }
            ENDHLSL
        }
    }
}
