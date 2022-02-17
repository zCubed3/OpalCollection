Shader "Opal/Lit/BRDF"
{
    Properties
    {
        [Header(Textures)]
        _MainTex ("Texture", 2D) = "white" {}
        _BumpMap ("Normal", 2D) = "bump" {}
        _EmissionMap ("Emission Map", 2D) = "black" {}
        _OcclusionMap ("Occlusion Map", 2D) = "white" {}

        _BRDFTex ("BRDF Ramp", 2D) = "white" {}
        
        [Header(Colors)]
        _Color ("Color", Color) = (1.0, 1.0, 1.0, 1.0)
        [HDR] _EmissionColor ("Emission Color", Color) = (1.0, 1.0, 1.0, 1.0)

        [Header(Fixes)]
        _NormalDepth ("Normal Depth (tweak for weird normals)", float) = 1

        [Header(Material)]
        _Roughness ("Roughness", Range(0, 1)) = 0.1
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Hardness ("Light Hardness", Range(0, 1)) = 1.0

        [Header(Toggles)]
        [Toggle(RECIEVE_SHADOWS)] _RecieveShadowsToggle("Recieve Shadows", Int) = 1

        [HideInInspector] _PBRModel ("PBR Model", int) = 0
    }
    
    CustomEditor "Opal.OpalBRDFEditor"

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

            #pragma shader_feature RECIEVE_SHADOWS
            #pragma shader_feature HAS_BRDF_MAP
            #pragma shader_feature HAS_BUMP_MAP
            #pragma shader_feature HAS_AO_MAP
            #pragma shader_feature RETROREFLECTIVE

            #ifndef RECIEVE_SHADOWS
            #undef SHADOWS_SCREEN 
            #undef SHADOWS_DEPTH
            #undef SHADOWS_CUBE
            #undef SHADOWS_SOFT
            #endif
            
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
                
            #ifdef HAS_BUMP_MAP
                float3 tangent : NORMAL1;
                float3 binormal : NORMAL2;
            #endif

                fixed3 ambient : TEXCOORD3;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex, _BumpMap, _EmissionMap, _OcclusionMap;
            sampler2D _BRDFTex;
            half _Roughness, _Hardness, _Metallic, _NormalDepth;
            fixed3 _EmissionColor, _Color;

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

                #ifdef HAS_BUMP_MAP

                o.normal = normalize(UnityObjectToWorldNormal(v.normal));
                o.tangent = normalize(UnityObjectToWorldDir(v.tangent));
                o.binormal = normalize(cross(o.normal, o.tangent) * v.tangent.w);

                #else

                o.normal = UnityObjectToWorldNormal(v.normal);
                
                #endif

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
                color.rgb *= _Color;

            #ifdef HAS_BUMP_MAP         
                float3 rawNormal = UnpackNormal(tex2D(_BumpMap, i.uv));
                rawNormal.z = _NormalDepth;

                float3x3 tan2World = float3x3(
					i.tangent,
					i.binormal,
					i.normal
				);

                half3 normal = normalize(mul(rawNormal, tan2World));
            #else
                half3 normal = normalize(i.normal);
            #endif

                half3 vDir = normalize(_WorldSpaceCameraPos - i.wPos);

                half3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                half NDotV = saturate(dot(normal, vDir));

                half clampMetallic = min(1.0, max(0.001, _Metallic));
                half clampRoughness = min(1.0, max(0.001, _Roughness));

                half3 F0 = lerp((0.04).xxx, color.rgb, clampMetallic);
                half3 F = FresnelSchlickRoughness(NDotV, F0, clampRoughness);

            #ifdef RETROREFLECTIVE
                #define NO_ISOTROPIC

                half3 back = reflect(-vDir, normal);
                half3 halfway = normalize(light + back);
                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, back, light, clampRoughness);

                fixed3 specular = F * smith * distrib * _LightColor0;
            #endif

            #ifndef NO_ISOTROPIC
                half3 halfway = normalize(light + vDir);
                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, vDir, light, clampRoughness);

                fixed3 specular = F * smith * distrib * _LightColor0;
            #endif

                half NDotH = saturate(dot(normal, halfway));
                half rawNDotL = dot(normal, light);

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

            #ifdef HAS_BRDF_MAP
                float brdfX = 0;
                float brdfY = NDotV;

                if (_Hardness < 1){
			        float HardnessHalfed = _Hardness * 0.5;
			        brdfX = max(0.0, ((rawNDotL * HardnessHalfed) + 1 - HardnessHalfed));	
                } else {			
                    brdfX = saturate((rawNDotL + 1) * 0.5);
			    }

                // To be safe
                brdfX = saturate(brdfX);

                fixed4 brdf = tex2D(_BRDFTex, float2(brdfX, brdfY));
            #else
                fixed4 brdf = saturate(rawNDotL);
            #endif

            #ifdef HAS_AO_MAP 
                half ao = tex2D(_OcclusionMap, i.uv).r;
            #else
                half ao = 1;
            #endif

                fixed3 brdfFinal = brdf.rgb * atten * _LightColor0 * lerp(1, F0, _Metallic);
                brdfFinal += specular;
                brdfFinal *= ao;
                brdfFinal += tex2D(_EmissionMap, i.uv).rgb * _EmissionColor;

                fixed3 reflection = SampleSpecular(i.wPos, normal, _Roughness) * F;
                color.rgb *= brdfFinal + i.ambient;
                color.rgb += reflection;

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

            #pragma shader_feature RECIEVE_SHADOWS
            #pragma shader_feature HAS_BRDF_MAP
            #pragma shader_feature HAS_BUMP_MAP
            #pragma shader_feature HAS_AO_MAP
            #pragma shader_feature RETROREFLECTIVE

            #ifndef RECIEVE_SHADOWS
            #undef SHADOWS_SCREEN 
            #undef SHADOWS_DEPTH
            #undef SHADOWS_CUBE
            #undef SHADOWS_SOFT
            #endif
            
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

            #ifdef HAS_BUMP_MAP
                float3 tangent : NORMAL1;
                float3 binormal : NORMAL2;
            #endif

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex, _BumpMap, _OcclusionMap;
            sampler2D _BRDFTex;
            half _Roughness, _Hardness, _Metallic, _NormalDepth;
            fixed3 _Color;

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

            #ifdef HAS_BUMP_MAP
                o.normal = normalize(UnityObjectToWorldNormal(v.normal));
                o.tangent = normalize(UnityObjectToWorldDir(v.tangent));
                o.binormal = normalize(cross(o.normal, o.tangent) * v.tangent.w);
            #else
                o.normal = UnityObjectToWorldNormal(v.normal);
            #endif

                o.uv = v.uv;

                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_FOG(o, o.pos);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                fixed4 color = tex2D(_MainTex, i.uv);
                color.rgb *= _Color;
                
            #ifdef HAS_BUMP_MAP                
                float3 rawNormal = UnpackNormal(tex2D(_BumpMap, i.uv));
                rawNormal.z = _NormalDepth;

                float3x3 tan2World = float3x3(
					i.tangent,
					i.binormal,
					i.normal
				);

                half3 normal = normalize(mul(rawNormal, tan2World));
            #else
                half3 normal = normalize(i.normal);
            #endif

                half3 vDir = normalize(_WorldSpaceCameraPos - i.wPos);

                half3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                half NDotV = saturate(dot(normal, vDir));

                half clampMetallic = min(1.0, max(0.001, _Metallic));
                half clampRoughness = min(1.0, max(0.001, _Roughness));

                half3 F0 = lerp((0.04).xxx, color.rgb, clampMetallic);
                half3 F = FresnelSchlickRoughness(NDotV, F0, clampRoughness);

            #ifdef RETROREFLECTIVE
                #define NO_ISOTROPIC

                half3 back = reflect(-vDir, normal);
                half3 halfway = normalize(light + back);
                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, back, light, clampRoughness);

                fixed3 specular = F * smith * distrib * _LightColor0;
            #endif

            #ifndef NO_ISOTROPIC
                half3 halfway = normalize(light + vDir);
                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, vDir, light, clampRoughness);

                fixed3 specular = F * smith * distrib * _LightColor0;
            #endif

                half NDotH = saturate(dot(normal, halfway));
                half rawNDotL = dot(normal, light);

                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

            #ifdef HAS_BRDF_MAP
                float brdfX = 0;
                float brdfY = NDotV;

                if (_Hardness < 1){
			        float HardnessHalfed = _Hardness * 0.5;
			        brdfX = max(0.0, ((rawNDotL * HardnessHalfed) + 1 - HardnessHalfed));	
                } else {			
                    brdfX = saturate((rawNDotL + 1) * 0.5);
			    }

                // To be safe
                brdfX = saturate(brdfX);

                fixed4 brdf = tex2D(_BRDFTex, float2(brdfX, brdfY));
            #else
                fixed4 brdf = saturate(rawNDotL);
            #endif

            #ifdef HAS_AO_MAP 
                half ao = tex2D(_OcclusionMap, i.uv).r;
            #else
                half ao = 1;
            #endif
                fixed3 brdfFinal = brdf.rgb * atten * _LightColor0 * lerp(1, F0, _Metallic);
                brdfFinal += specular;
                brdfFinal *= ao;

                color.rgb *= brdfFinal;

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
