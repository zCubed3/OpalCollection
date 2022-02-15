Shader "Opal/Geometry/Outline"
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
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag

            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2g
            {
                float4 vertex : SV_POSITION;
                float3 normal : NORMAL0;
                float2 uv : TEXCOORD0;
            };

            struct g2f 
            {
                float4 vertex : SV_POSITION;
                float3 normal : NORMAL0;
                float2 uv : TEXCOORD0;
                float extruded : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float _ExtrusionAmount;
            half3 _OutlineColor;

            v2g vert (appdata v)
            {
                v2g o;

                o.vertex = v.vertex;
                o.uv = v.uv;
                o.normal = v.normal;

                return o;
            }

            [maxvertexcount(6)]
            void geom(triangle v2g input[3], inout TriangleStream<g2f> stream) {
                for (int i = 0; i < 3; i++) {
                    g2f o;
                    v2g v = input[i];

                    o.vertex = UnityObjectToClipPos(v.vertex);
                    o.normal = v.normal;
                    o.uv = v.uv;
                    o.extruded = 0;

                    stream.Append(o);
                }

                stream.RestartStrip();

                for (int i = 2; i >= 0; i--) {
                    g2f o;
                    v2g v = input[i];

                    float3 shift = v.normal * _ExtrusionAmount;

                    o.vertex = UnityObjectToClipPos(v.vertex + shift);
                    o.normal = -v.normal;
                    o.uv = v.uv;
                    o.extruded = 1;

                    stream.Append(o);
                }
            }

            fixed4 frag (g2f i) : SV_Target
            {
                fixed4 col = 0;

                if (i.extruded) {
                    col = fixed4(_OutlineColor, 1);
                } else {
                    col = tex2D(_MainTex, i.uv);
                }

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
