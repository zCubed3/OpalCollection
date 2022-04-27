Shader "Opal/Geometry/OutlineVertex"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _ExtrusionAmount ("Extrusion Amount", float) = 0.01
        [HDR] _OutlineColor ("Outline Color", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            Tags { "LightMode"="ForwardBase" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 normal : NORMAL0;
                float2 uv : TEXCOORD0;
                float3 wPos : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.normal = v.normal;
                o.wPos = mul(unity_ObjectToWorld, v.vertex);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                half3 normal = normalize(i.normal);

                fixed4 col = 0;
                col = tex2D(_MainTex, i.uv);

                half3 vDir = normalize(_WorldSpaceCameraPos - i.wPos);

                half3 light = _WorldSpaceLightPos0;
                if (_WorldSpaceLightPos0.w > 0) {
                    light = normalize(_WorldSpaceLightPos0 - i.wPos);
                }

                half NDotL = saturate(dot(normal, light));

                col.rgb *= ceil(NDotL);

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);

                return col;
            }
            ENDHLSL
        }
        Pass
        {
            Cull Front
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 normal : NORMAL0;
                float2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float _ExtrusionAmount;
            half3 _OutlineColor;

            v2f vert (appdata v)
            {
                v2f o;

                o.uv = v.uv;
                o.normal = v.normal;
                o.vertex = UnityObjectToClipPos(v.vertex + o.normal * _ExtrusionAmount);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = fixed4(_OutlineColor, 1);
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDHLSL
        }
    }
}
