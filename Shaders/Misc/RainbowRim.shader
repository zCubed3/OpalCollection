Shader "Opal/Misc/RainbowRim"
{
    Properties
    {
        _Speed ("Speed", float) = 1
        [Toggle] _Inverted ("Inverted", Int) = 0
        _Power ("Power", float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 normal : NORMAL0;
                float3 wPos : TEXCOORD2;

                UNITY_FOG_COORDS(1)
            };

            int _Inverted;
            float _Power, _Speed;

            float3 FresnelSchlick(float cosTheta, float3 F0, float fPow) {
               return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), fPow);
            }

            fixed3 HSV(float3 c) {
                float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
                return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
            }

            v2f vert (appdata v)
            {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.wPos = mul(unity_ObjectToWorld, v.vertex);

                UNITY_TRANSFER_FOG(o,o.vertex);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 vDir = normalize(_WorldSpaceCameraPos - i.wPos);
                float3 normal = normalize(i.normal);

                float NDotV = saturate(dot(normal, vDir));
                float F = pow(_Inverted ? NDotV : 1 - NDotV, _Power);
                fixed3 col = HSV(float3(_Time.x, 1, 1)) * F;

                return fixed4(col, 1);
            }
            ENDCG
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
