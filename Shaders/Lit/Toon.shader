Shader "Opal/Lit/Toon"
{
    Properties
    {
        [Header(Material)]
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1.0, 1.0, 1.0, 1.0)

        _Specular ("Specular", Range(0, 1)) = 0.0
        _Roughness ("Roughness", Range(0, 1)) = 1.0
        _Metallic ("Metallic", Range(0, 1)) = 0.0

        [Header(Lighting)]
        _ShadingBands ("Bands", Int) = 2
        _ShadingPower ("Softness", Range(0.01, 1)) = 1.0
        _AmbientBoost ("Ambient Boost", Range(0, 1)) = 0.1

        [Header(Outline)]
        _OutlineColor ("Color", Color) = (0.0, 0.0, 0.0, 1.0)
        _OutlineExtrusion ("Extrusion", float) = 0.001
    }
    SubShader
    {
        LOD 100
        
        //
        // Lighting
        // 
        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode"="ForwardBase" }
            Blend SrcAlpha OneMinusSrcAlpha 

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            
            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"
            #include "UnityStandardBRDF.cginc"
            #include "UnityPBSLighting.cginc"
            #include "AutoLight.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 wPos : TEXCOORD0;
                float2 uv : TEXCOORD9;
                float3 normal : TEXCOORD8;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            fixed4 _Color;
            int _ShadingBands;
            float _ShadingPower;
            float _AmbientBoost;
            float _Specular, _Roughness, _Metallic;

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v)
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                o.wPos = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.uv = v.uv;

                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 view = normalize(_WorldSpaceCameraPos - i.wPos);
                float3 normal = normalize(i.normal);
                
                float3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                float3 halfway = normalize(view + light);

                float NDotV = saturate(dot(view, normal));
                float NDotL = saturate(dot(light, normal));
                float NDotH = saturate(dot(halfway, normal));

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

                float lit = (ceil(pow(NDotL, _ShadingPower) * atten * _ShadingBands) / _ShadingBands);

                float smooth = (1 - _Roughness);

                float spec = (ceil(pow(NDotH, max(0.1, smooth * 10000)) * atten * NDotL)) * _Specular;

                fixed3 base = _Color * tex2D(_MainTex, i.uv);
                fixed3 specular = lerp(1, _Color, _Metallic) * spec * _LightColor0;
                fixed3 color = (base * _AmbientBoost) + (base * _LightColor0 * lit) + specular;

                UNITY_APPLY_FOG(i.fogCoord, color);

                return fixed4(color, _Color.a);
            }
            ENDHLSL
        }
        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode"="ForwardAdd" }
            Blend One One 
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog
            #pragma multi_compile_fwdadd_fullshadow
            
            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"
            #include "UnityStandardBRDF.cginc"
            #include "UnityPBSLighting.cginc"
            #include "AutoLight.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 wPos : TEXCOORD0;
                float2 uv : TEXCOORD9;
                float3 normal : TEXCOORD8;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            fixed4 _Color;
            int _ShadingBands;
            float _ShadingPower;
            float _Specular, _Roughness, _Metallic;

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v)
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                o.wPos = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.uv = v.uv;

                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 view = normalize(_WorldSpaceCameraPos - i.wPos);
                float3 normal = normalize(i.normal);
                
                float3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                float3 halfway = normalize(view + light);

                float NDotV = saturate(dot(view, normal));
                float NDotL = saturate(dot(light, normal));
                float NDotH = saturate(dot(halfway, normal));

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

                float lit = (ceil(pow(NDotL, _ShadingPower) * atten * _ShadingBands) / _ShadingBands);

                float smooth = (1 - _Roughness);

                float spec = (ceil(pow(NDotH, max(0.1, smooth * 10000)) * atten * NDotL)) * _Specular;

                fixed3 base = _Color * tex2D(_MainTex, i.uv);
                fixed3 specular = lerp(1, _Color, _Metallic) * spec * _LightColor0;
                fixed3 color = lerp(0, base * _LightColor0, lit) + specular;

                UNITY_APPLY_FOG(i.fogCoord, color);

                return fixed4(color, 1) * _Color.a;
            }
            ENDHLSL
        }
        //
        // Outline
        //
        Pass 
        {
            Cull Front
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog
            
            #pragma target 5.0

            #include "UnityCG.cginc"

            float _OutlineExtrusion;
            fixed4 _OutlineColor;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;

                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v)
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                float3 offset = normalize(v.normal) * _OutlineExtrusion;
                o.pos = UnityObjectToClipPos(v.vertex + offset);

                o.uv = v.uv;

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                fixed4 color = _OutlineColor;
                UNITY_APPLY_FOG(i.fogCoord, color);
                return color;
            }


            ENDHLSL
        }
        Pass
        {
            Tags { "LightMode"="ShadowCaster" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_shadowcaster
            #include "UnityCG.cginc"

            struct v2f { 
                V2F_SHADOW_CASTER;
            };

            v2f vert(appdata_base v)
            {
                v2f o;
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDCG
        }
    }
}
