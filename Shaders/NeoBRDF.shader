Shader "zCubed/NeoBRDF"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _BumpMap ("Normal", 2D) = "bump" {}
        _BRDFTex ("BRDF Ramp", 2D) = "white" {}

        [Header(Fixes)]
        _NormalDepth ("Normal Depth (tweak for weird normals)", float) = 2

        [Header(Material)]
        _Roughness ("Roughness", Range(0, 1)) = 0.1
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Hardness ("Light Hardness", Range(0, 1)) = 1.0
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

            sampler2D _MainTex, _BumpMap;
            sampler2D _BRDFTex;
            half _Roughness, _Hardness, _Metallic, _NormalDepth;

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
                half rawNDotL = dot(normal, light);

                half clampMetallic = min(1.0, max(0.001, _Metallic));
                half clampRoughness = min(1.0, max(0.001, _Roughness));

                half3 F0 = lerp((0.04).xxx, color.rgb, clampMetallic);
                half3 F = FresnelSchlickRoughness(NDotV, F0, clampRoughness);

                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, vDir, light, clampRoughness);
                
                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

                float brdfX = 0;
                float brdfY = NDotV;

                if (_Hardness < 1){
			        float HardnessHalfed = _Hardness * 0.5;
			        brdfX = max(0.0, ((rawNDotL * HardnessHalfed) + 1 - HardnessHalfed));	
                } else {			
                    brdfX = saturate((rawNDotL + 1) * 0.5);
			    }

                fixed4 brdf = tex2D(_BRDFTex, float2(brdfX, brdfY));

                fixed3 specular = F * smith * distrib * _LightColor0;
                fixed3 brdfFinal = brdf.rgb * atten * _LightColor0 * lerp(1, F0, _Metallic);
                brdfFinal += specular;

                color.rgb *= brdfFinal + i.ambient;

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

                fixed3 ambient : TEXCOORD3;

                SHADOW_COORDS(4)
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex, _BumpMap;
            sampler2D _BRDFTex;
            half _Roughness, _Hardness, _Metallic, _NormalDepth;

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
                half rawNDotL = dot(normal, light);

                half clampMetallic = min(1.0, max(0.001, _Metallic));
                half clampRoughness = min(1.0, max(0.001, _Roughness));

                half3 F0 = lerp((0.04).xxx, color.rgb, clampMetallic);
                half3 F = FresnelSchlickRoughness(NDotV, F0, clampRoughness);

                half distrib = DistributionGGX(normal, halfway, clampRoughness);
                half smith = GeometrySmith(normal, vDir, light, clampRoughness);
                
                UNITY_LIGHT_ATTENUATION(atten, i, i.wPos)

                float brdfX = 0;
                float brdfY = NDotV;

                if (_Hardness < 1){
			        float HardnessHalfed = _Hardness * 0.5;
			        brdfX = max(0.0, ((rawNDotL * HardnessHalfed) + 1 - HardnessHalfed));	
                } else {			
                    brdfX = saturate((rawNDotL + 1) * 0.5);
			    }

                fixed4 brdf = tex2D(_BRDFTex, float2(brdfX, brdfY));

                fixed3 specular = F * smith * distrib * _LightColor0;

                fixed3 brdfFinal = brdf.rgb * atten * _LightColor0 * lerp(1, F0, _Metallic);
                brdfFinal += specular;

                color.rgb *= brdfFinal + i.ambient;

                UNITY_APPLY_FOG(i.fogCoord, color);
                return color;
            }
            ENDHLSL
        }
    }
    Fallback "VertexLit"
}
