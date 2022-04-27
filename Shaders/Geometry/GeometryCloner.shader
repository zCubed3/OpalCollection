Shader "Opal/Geometry/Cloner"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _CloneDistance ("Clone Distance", float) = 1.0
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

            float _CloneDistance;

            v2g vert (appdata v)
            {
                v2g o;

                o.vertex = v.vertex;
                o.uv = v.uv;
                o.normal = v.normal;

                return o;
            }

            [maxvertexcount(15)]
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

                for (int d = 0; d < 1; d++) {
                    for (int s = 0; s < 4; s++) {
                        float f = s / 4.0;
                        f *= 3.141592654 * 2;

                        float3 offset = float3(sin(f), 0, cos(f)) * (_CloneDistance + d);
                        for (int i = 0; i < 3; i++) {
                            g2f o;
                            v2g v = input[i];
    
                            float3 pos = mul(unity_ObjectToWorld, v.vertex);
                            pos += offset;
    
                            o.vertex = UnityWorldToClipPos(pos);
                            o.normal = v.normal;
                            o.uv = v.uv;
                            o.extruded = 0;
    
                            stream.Append(o);
                        }
    
                        stream.RestartStrip();
                    }
                }
            }

            fixed4 frag (g2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
        Pass 
        {
            Tags {"LightMode"="ShadowCaster"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag
            
            #pragma multi_compile_shadowcaster
            #include "UnityCG.cginc"

            float _CloneDistance;

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2g
            {
                float4 vertex : POSITION;
            };

            struct g2f 
            {
                float4 vertex : SV_POSITION;
            };

            v2g vert(appdata v)
            {
                v2g o;
                o.vertex = v.vertex;
                return o;
            }

            [maxvertexcount(15)]
            void geom(triangle v2g input[3], inout TriangleStream<g2f> stream) {
                for (int i = 0; i < 3; i++) {
                    g2f o;
                    v2g v = input[i];

                    o.vertex = UnityObjectToClipPos(v.vertex);

                    stream.Append(o);
                }

                stream.RestartStrip();

                for (int d = 0; d < 1; d++) {
                    for (int s = 0; s < 4; s++) {
                        float f = s / 4.0;
                        f *= 3.141592654 * 2;

                        float3 offset = float3(sin(f), 0, cos(f)) * (_CloneDistance + d);

                        for (int i = 0; i < 3; i++) {
                            g2f o;
                            v2g v = input[i];

                            float3 pos = mul(unity_ObjectToWorld, v.vertex);
                            pos += offset;

                            o.vertex = UnityWorldToClipPos(pos);

                            stream.Append(o);
                        }

                        stream.RestartStrip();
                    }
                }
            }

            float4 frag(g2f i) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }
}
