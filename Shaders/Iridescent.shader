Shader "Opal/Iridescent"
{
    Properties
    {
        [Header(Textures)]
        _MainTex ("Texture", 2D) = "white" {}
        _BumpMap ("Normal", 2D) = "bump" {}
        _EmissionMap ("Emission Map", 2D) = "black" {}
        _OcclusionMap ("Occlusion Map", 2D) = "white" {}

        _IridescentRamp ("Iridescent Ramp", 2D) = "white" {}

        [Header(Colors)]
        [HDR] _EmissionColor ("Emission Color", Color) = (1.0, 1.0, 1.0, 1.0)

        [Header(Iridescent)]
        [Toggle] _Inverted ("Inverted", int) = 0
        [Toggle] _Reverse ("Reversed", int) = 0
        [Toggle(_EMISSIVE_ON)] _Emissive ("Emissive", int) = 0
        _SchlickFactor ("IOR (careful changing this!)", float) = 0.04
        _FresPow ("Fresnel Power", float) = 1.0
        _ScrollVelocity ("Scroll Velocity", float) = 0
        _RampIntensity ("Ramp Intensity", float) = 1

        [Header(Fixes)]
        _NormalDepth ("Normal Depth (tweak for weird normals)", float) = 2

        [Header(Material)]
        _Roughness ("Roughness", Range(0, 1)) = 0.1
        _Metallic ("Metallic", Range(0, 1)) = 0
    }
    SubShader
    {
        LOD 100

        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode"="ForwardBase" }
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            
            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "UnityInstancing.cginc"
            #include "AutoLight.cginc"
            #include "UnityLightingCommon.cginc"
            #include "UnityStandardBRDF.cginc"
            #include "UnityPBSLighting.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;

                float3 normal : NORMAL0;
                float3 tangent : NORMAL1;
                float3 binormal : NORMAL2;

                fixed3 ambient : TEXCOORD3;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex, _BumpMap, _EmissionMap, _OcclusionMap;
            sampler2D _IridescentRamp;
            half _Roughness, _Metallic, _NormalDepth, _SchlickFactor, _FresPow, _ScrollVelocity, _RampIntensity;
            int _Inverted, _Reverse, _Emissive;
            fixed3 _EmissionColor;

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

                o.normal = normalize(UnityObjectToWorldNormal(v.normal));
                o.tangent = normalize(UnityObjectToWorldDir(v.tangent));
                o.binormal = normalize(cross(o.normal, o.tangent));

                o.uv = v.uv;
                o.ambient = ShadeSH9(float4(UnityObjectToWorldNormal(v.normal), 1));

                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                fixed4 color = tex2D(_MainTex, i.uv);
                
                float3 rawNormal = UnpackNormal(tex2D(_BumpMap, i.uv));
                rawNormal.z = _NormalDepth;

                float3x3 tan2World = float3x3(
					i.tangent,
					i.binormal,
					i.normal
				);

                half3 normal = normalize(mul(rawNormal, tan2World));
                half3 vDir = normalize(_WorldSpaceCameraPos - i.wPos);

                half3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                half3 halfway = normalize(light + vDir);
                half NDotH = saturate(dot(normal, halfway));
                half NDotV = saturate(dot(normal, vDir));
                half NDotL = saturate(dot(normal, light));

                half clampMetallic = min(1.0, max(0.001, _Metallic));
                half clampRoughness = min(1.0, max(0.001, _Roughness));

                half3 F0 = lerp((0.04).xxx, color.rgb, clampMetallic);
                half3 F = FresnelSchlickRoughness(NDotV, F0, clampRoughness);

                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, vDir, light, clampRoughness);
                
                half ao = tex2D(_OcclusionMap, i.uv).r;

                float NDotVgloss = NDotV;
                NDotVgloss = _Inverted ? 1 - NDotVgloss : NDotVgloss;
                NDotVgloss = FresnelSchlick(1 - NDotVgloss, (_SchlickFactor).xxx, _FresPow);
                 
                float NDotV2 = _Reverse ? 1 - NDotVgloss : NDotVgloss;

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

                fixed4 rampCol = tex2D(_IridescentRamp, float2(NDotV2 + (_Time.x * _ScrollVelocity), 0.5f)) * _RampIntensity;
                
                fixed3 reflection = SampleSpecular(i.wPos, normal, _Roughness) * F;
                fixed3 ambient = color.rgb * i.ambient;
                fixed3 specular = F * smith * distrib * _LightColor0;
                fixed3 emission = (tex2D(_EmissionMap, i.uv) * _EmissionColor) + (rampCol * _Emissive);

                color.rgb = (color.rgb + rampCol) * atten * NDotL * ao * _LightColor0;
                color.rgb += ambient + specular + reflection + emission;

                UNITY_APPLY_FOG(i.fogCoord, color);
                return color;
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
            #pragma shader_feature _EMISSIVE_ON

            #pragma target 5.0

            #include "UnityCG.cginc"
            #include "UnityInstancing.cginc"
            #include "AutoLight.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;

                float3 normal : NORMAL0;
                float3 tangent : NORMAL1;
                float3 binormal : NORMAL2;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex, _BumpMap, _EmissionMap, _OcclusionMap;
            sampler2D _IridescentRamp;
            half _Roughness, _Metallic, _NormalDepth, _SchlickFactor, _FresPow, _ScrollVelocity, _RampIntensity;
            int _Inverted, _Reverse, _Emissive;
            fixed3 _EmissionColor;

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
            //...

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v)
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                o.wPos = mul(unity_ObjectToWorld, v.vertex);

                o.normal = normalize(UnityObjectToWorldNormal(v.normal));
                o.tangent = normalize(UnityObjectToWorldDir(v.tangent));
                o.binormal = normalize(cross(o.normal, o.tangent));

                o.uv = v.uv;

                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                fixed4 color = tex2D(_MainTex, i.uv);
                
                float3 rawNormal = UnpackNormal(tex2D(_BumpMap, i.uv));
                rawNormal.z = _NormalDepth;

                float3x3 tan2World = float3x3(
					i.tangent,
					i.binormal,
					i.normal
				);

                half3 normal = normalize(mul(rawNormal, tan2World));
                half3 vDir = normalize(_WorldSpaceCameraPos - i.wPos);

                half3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                half3 halfway = normalize(light + vDir);
                half NDotH = saturate(dot(normal, halfway));
                half NDotV = saturate(dot(normal, vDir));
                half NDotL = saturate(dot(normal, light));

                half clampMetallic = min(1.0, max(0.001, _Metallic));
                half clampRoughness = min(1.0, max(0.001, _Roughness));

                half3 F0 = lerp((0.04).xxx, color.rgb, clampMetallic);
                half3 F = FresnelSchlickRoughness(NDotV, F0, clampRoughness);

                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, vDir, light, clampRoughness);
                
                half ao = tex2D(_OcclusionMap, i.uv).r;

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

#ifdef _EMISSIVE_ON
                fixed4 rampCol = 0;
#else
                float NDotVgloss = NDotV;
                NDotVgloss = _Inverted ? 1 - NDotVgloss : NDotVgloss;
                NDotVgloss = FresnelSchlick(1 - NDotVgloss, (_SchlickFactor).xxx, _FresPow);
                 
                float NDotV2 = _Reverse ? 1 - NDotVgloss : NDotVgloss;
                
                fixed4 rampCol = tex2D(_IridescentRamp, float2(NDotV2 + (_Time.x * _ScrollVelocity), 0.5f)) * _RampIntensity;
#endif

                fixed3 specular = F * smith * distrib * _LightColor0;

                color.rgb = (color.rgb + rampCol) * atten * NDotL * ao * _LightColor0;
                color.rgb += specular;

                UNITY_APPLY_FOG(i.fogCoord, color);
                return color;
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
