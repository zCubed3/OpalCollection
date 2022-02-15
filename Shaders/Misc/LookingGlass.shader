Shader "Opal/Misc/LookingGlass"
{
    Properties
    {
        _MainTex ("Texture", Cube) = "white" {}
        _EffectMask ("Mask", 2D) = "white" {}

        [Header(Material)]
        _FresnelPow ("Rim Frensel Pow", float) = 2
        _Roughness ("Roughness", Range(0.000001, 1)) = 0.1
        _EdgeGlow ("Edge Glow", Color) = (0, 0, 0, 0)
        _InterRefractPow ("Inter Refract Pow", float) = 4

        [Header(Ambiance)]
        _SpinSpeed ("Spin Speed", Vector) = (0.5, 0.5, 0.5, 0.0)
    }
    SubShader
    {
        LOD 100

        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode"="ForwardBase" }
            //Blend SrcAlpha OneMinusSrcAlpha 
            Cull Back
            //ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // make fog work
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
                float3x3 Spin : TEXCOORD1;
                float2 uv : TEXCOORD9;
                float3 normal : TEXCOORD8;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            samplerCUBE _MainTex;
            sampler2D _EffectMask;
            half3 _SpinSpeed;
            half _FresnelPow, _MinLOD, _Roughness, _InterRefractPow;
            fixed3 _EdgeGlow;

            #define PI 3.141592654

            //
            // Approximations
            //
            // https://learnopengl.com/PBR/IBL/Diffuse-irradiance
            float3 FresnelSchlick(float cosTheta, float3 F0, float fPow) {
               return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), fPow);
            }

            float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
               return F0 + (max((1.0 - roughness).xxx, F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
            }

            //
            // Scattering
            //
            float DistributionGGX(float3 N, float3 H, float a)
            {
               float a2     = a*a;
               float NdotH  = max(dot(N, H), 0.0);
               float NdotH2 = NdotH*NdotH;

               float nom    = a2;
               float denom  = (NdotH2 * (a2 - 1.0) + 1.0);
               denom        = PI * denom * denom;

               return nom / denom;
            }

            float GeometrySchlickGGX(float NdotV, float k)
            {
                float nom   = NdotV;
                float denom = NdotV * (1.0 - k) + k;

                return nom / denom;
            }

            float GeometrySmith(float3 N, float3 V, float3 L, float k)
            {
                float NdotV = max(dot(N, V), 0.0);
                float NdotL = max(dot(N, L), 0.0);
                float ggx1 = GeometrySchlickGGX(NdotV, k);
                float ggx2 = GeometrySchlickGGX(NdotL, k);

                return ggx1 * ggx2;
            }

            //
            // Helpers
            //
            float3 ProjectDirToBox(float3 vDir, float3 wPos, float3 rPos, float3 rBoxMin, float3 rBoxMax) 
            {
                vDir = normalize(vDir);

                rBoxMin -= wPos;
                rBoxMax -= wPos;

                float x = (vDir.x > 0 ? rBoxMax.x : rBoxMin.x) / vDir.x;
                float y = (vDir.y > 0 ? rBoxMax.y : rBoxMin.y) / vDir.y;
                float z = (vDir.z > 0 ? rBoxMax.z : rBoxMin.z) / vDir.z;
                float scalar = min(min(x, y), z);

                return vDir * scalar + (wPos - rPos);
            }


            fixed3 SampleSpecular(float3 wPos, float3 wNormal, float roughness) 
            {
                float3 camDirection = normalize(wPos - _WorldSpaceCameraPos);
                float3 rDir = reflect(normalize(camDirection), normalize(wNormal));

            #if UNITY_SPECCUBE_BOX_PROJECTION
                [branch]
                if (unity_SpecCube0_ProbePosition.w > 0) {
                    rDir = ProjectDirToBox(rDir, wPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
                }
            #endif

            	Unity_GlossyEnvironmentData envData;
                envData.roughness = roughness;
                envData.reflUVW = rDir;

                fixed3 probe0 = Unity_GlossyEnvironment(
            		UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
            	);

            #if UNITY_SPECCUBE_BLENDING

                [branch]
                if (unity_SpecCube0_BoxMin.w >= 0.999999) {
                    return probe0;
                } else {
                
            #if UNITY_SPECCUBE_BOX_PROJECTION

                    [branch]
                    if (unity_SpecCube1_ProbePosition.w > 0) {
                        rDir = ProjectDirToBox(rDir, wPos, unity_SpecCube1_ProbePosition, unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);
                    }

                    envData.reflUVW = rDir;

            #endif

                    fixed3 probe1 = Unity_GlossyEnvironment(
            	    	UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0),
            	    	unity_SpecCube0_HDR, envData
            	    ); 

                    return lerp(probe1, probe0, unity_SpecCube0_BoxMin.w);

                }
            #else
                return probe0;
            #endif
            }

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v)
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                o.wPos = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);

                float3 time = _Time.xxx * _SpinSpeed;
                
                float3x3 xSpin = float3x3(
                    1, 0, 0,
                    0, cos(time.x), -sin(time.x),
                    0, sin(time.x), cos(time.x)
                );

                float3x3 ySpin = float3x3(
                    cos(time.y), 0, sin(time.y),
                    0, 1, 0,
                    -sin(time.y), 0, cos(time.y)
                );

                float3x3 zSpin = float3x3(
                    cos(time.z), -sin(time.z), 0,
                    sin(time.z), cos(time.z), 0,
                    0, 0, 1
                );

                o.Spin = mul(zSpin, mul(ySpin, xSpin));

                o.uv = v.uv;

                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                half3 vVector = _WorldSpaceCameraPos - i.wPos;
                half vLen = length(vVector);

                half3 vDir = vVector / vLen;
                half3 normal = normalize(i.normal);
                
                half3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                half3 halfway = normalize(light + vDir);
                half NDotH = saturate(dot(normal, halfway));
                half NDotV = saturate(dot(normal, vDir));

                half distrib = DistributionGGX(normal, halfway, _Roughness);
                half smith = GeometrySmith(normal, vDir, light, _Roughness);
                
                half3 S0 = (0.04).xxx;
                half S = FresnelSchlickRoughness(NDotV, S0, _Roughness);

                half spiq = smith * distrib;

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)
                spiq *= atten * S;

                half3 F0 = (0.04).xxx;
                half3 F = FresnelSchlick(NDotV, F0, _FresnelPow);

                half3 interDir = lerp(vDir, normal, pow(F, _InterRefractPow));
                half3 SpinDir = normalize(mul(i.Spin, interDir));

                //fixed3 qube = texCUBElod(_MainTex, float4(SpinDir, fresnel.x * _MinLOD));
                fixed3 qube = texCUBElod(_MainTex, float4(SpinDir, 0));
                //fixed3 qube = texCUBE(_MainTex, SpinDir);

                //fixed3 specular = SampleSpecular(i.wPos, i.normal, _Roughness);

                half mask = tex2D(_EffectMask, i.uv).r;
                qube *= mask;

                fixed3 color = lerp(qube, _EdgeGlow, F);
                color += spiq.xxx * _LightColor0;

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, color);

                return fixed4(color, 1);
                //return fixed4(color, 1 - fresnel.x);
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
            #pragma multi_compile_fwdadd_fullshadows
            
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

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 wPos : TEXCOORD0;
                float3 normal : NORMAL0;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            samplerCUBE _MainTex;
            half3 _SpinSpeed;
            half _FresnelPow, _MinLOD, _Roughness, _BlinnPhongPow;

            #define PI 3.141592654

            //
            // Approximations
            //
            // https://learnopengl.com/PBR/IBL/Diffuse-irradiance
            float3 FresnelSchlick(float cosTheta, float3 F0, float fPow) {
               return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), fPow);
            }

            float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness) {
               return F0 + (max((1.0 - roughness).xxx, F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
            }

            //
            // Scattering
            //
            float DistributionGGX(float3 N, float3 H, float a)
            {
               float a2     = a*a;
               float NdotH  = max(dot(N, H), 0.0);
               float NdotH2 = NdotH*NdotH;

               float nom    = a2;
               float denom  = (NdotH2 * (a2 - 1.0) + 1.0);
               denom        = PI * denom * denom;

               return nom / denom;
            }

            float GeometrySchlickGGX(float NdotV, float k)
            {
                float nom   = NdotV;
                float denom = NdotV * (1.0 - k) + k;

                return nom / denom;
            }

            float GeometrySmith(float3 N, float3 V, float3 L, float k)
            {
                float NdotV = max(dot(N, V), 0.0);
                float NdotL = max(dot(N, L), 0.0);
                float ggx1 = GeometrySchlickGGX(NdotV, k);
                float ggx2 = GeometrySchlickGGX(NdotL, k);

                return ggx1 * ggx2;
            }

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v)
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                o.wPos = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                
                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                half3 vDir = normalize(_WorldSpaceCameraPos - i.wPos);
                half3 normal = normalize(i.normal);
                
                half3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                half3 halfway = normalize(light + vDir);
                half NDotH = saturate(dot(normal, halfway));
                half NDotV = saturate(dot(normal, vDir));

                half distrib = DistributionGGX(normal, halfway, _Roughness);
                half smith = GeometrySmith(normal, vDir, light, _Roughness);
                
                half3 S0 = (0.04).xxx;
                half S = FresnelSchlickRoughness(NDotV, S0, _Roughness);

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

                half spiq = smith * distrib * S * atten;

                fixed3 color = spiq.xxx * _LightColor0;

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, color);

                return fixed4(color, 0);
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
