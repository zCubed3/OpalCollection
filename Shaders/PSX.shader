Shader "Opal/PSX"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _FakeRes ("Fake Res", Vector) = (320, 240, 0, 0)
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode", Int) = 1

        [Toggle(UNLIT)] _UnlitToggle ("Unlit", Int) = 1
    }
    SubShader
    {
        LOD 100

        Cull [_CullMode]
        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode"="ForwardBase" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"

            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase

            #pragma shader_feature UNLIT

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float2 uv2 : TEXCOORD1;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                noperspective float2 uv : TEXCOORD0;

                #ifndef UNLIT
                float3 normal : NORMAL0;
                fixed3 ambient : TEXCOORD1;
                fixed3 lighting : TEXCOORD2;
                float3 world : TEXCOORD3;

                SHADOW_COORDS(4)
                #endif

                UNITY_FOG_COORDS(5)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            
            half4 _FakeRes;

            v2f vert (appdata v)
            {
                v2f o;

                o.pos = UnityObjectToClipPos(v.vertex);
                
                float4 snapVertex = o.pos;
                snapVertex.xyz /= snapVertex.w;
                snapVertex.xy = floor(_FakeRes.xy * snapVertex.xy) / _FakeRes.xy;
                snapVertex.xyz *= snapVertex.w;

                o.pos = snapVertex;
                
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                
                #ifndef UNLIT
                o.normal = UnityObjectToWorldNormal(v.normal);

                o.world = mul(unity_ObjectToWorld, v.vertex);
                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                o.ambient = ShadeSH9(float4(o.normal, 1)) + UNITY_LIGHTMODEL_AMBIENT.xyz;
                //o.ambient = 0;
                o.lighting = 0;

                if (_WorldSpaceLightPos0.w == 0) {
                    o.lighting += saturate(dot(o.normal, _WorldSpaceLightPos0)) * _LightColor0;
                } else {
                    float3 light = normalize(_WorldSpaceLightPos0 - o.world);
                    o.lighting += saturate(dot(o.normal, light)) * _LightColor0;
                }
                #endif

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);

                #ifndef UNLIT
                UNITY_LIGHT_ATTENUATION(atten, i, i.world)

                fixed3 light = col.rgb * i.lighting * atten;
                fixed3 ambient = col.rgb * i.ambient;
                col.rgb = light + ambient;
                #endif

                UNITY_APPLY_FOG(i.fogCoord, col);

                return col;
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

            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"

            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog

            #pragma shader_feature UNLIT

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float2 uv2 : TEXCOORD1;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                noperspective float2 uv : TEXCOORD0;

                #ifndef UNLIT
                float3 normal : NORMAL0;
                fixed3 ambient : TEXCOORD1;
                fixed3 lighting : TEXCOORD2;
                float3 world : TEXCOORD3;

                SHADOW_COORDS(4)
                #endif
                
                UNITY_FOG_COORDS(5)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            
            half4 _FakeRes;

            v2f vert (appdata v)
            {
                v2f o;

                o.pos = UnityObjectToClipPos(v.vertex);
                
                float4 snapVertex = o.pos;
                snapVertex.xyz /= snapVertex.w;
                snapVertex.xy = floor(_FakeRes.xy * snapVertex.xy) / _FakeRes.xy;
                snapVertex.xyz *= snapVertex.w;

                o.pos = snapVertex;
                
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                
                #ifndef UNLIT
                o.normal = UnityObjectToWorldNormal(v.normal);

                o.world = mul(unity_ObjectToWorld, v.vertex);
                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                //o.ambient = ShadeSH9(float4(o.normal, 1)) + UNITY_LIGHTMODEL_AMBIENT.xyz;
                o.ambient = 0;
                o.lighting = 0;

                if (_WorldSpaceLightPos0.w == 0) {
                    o.lighting += saturate(dot(o.normal, _WorldSpaceLightPos0)) * _LightColor0;
                } else {
                    float3 light = normalize(_WorldSpaceLightPos0 - o.world);
                    o.lighting += saturate(dot(o.normal, light)) * _LightColor0;
                }
                #endif

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);

                #ifndef UNLIT
                UNITY_LIGHT_ATTENUATION(atten, i, i.world)

                fixed3 light = col.rgb * i.lighting * atten;
                fixed3 ambient = col.rgb * i.ambient;
                col.rgb = light + ambient;
                #else
                return 0;
                #endif

                UNITY_APPLY_FOG(i.fogCoord, col);

                return col;
            }
            ENDHLSL
        }
        Pass
        {
            Tags {"LightMode"="ShadowCaster"}

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
