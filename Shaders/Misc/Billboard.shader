// Based on: https://en.wikibooks.org/wiki/Cg_Programming/Unity/Billboards
Shader "Opal/Unlit/Billboard"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Scale ("Scale", Vector) = (1.0, 1.0, 0.0, 0.0)
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        LOD 100
        ZWrite Off
        Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            float2 _Scale;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                
                //https://forum.unity.com/threads/can-i-get-the-scale-in-the-transform-of-the-object-i-attach-a-shader-to-if-so-how.418345/
                float3 worldScale = float3(
                    length(float3(unity_ObjectToWorld[0].x, unity_ObjectToWorld[1].x, unity_ObjectToWorld[2].x)), // scale x axis
                    length(float3(unity_ObjectToWorld[0].y, unity_ObjectToWorld[1].y, unity_ObjectToWorld[2].y)), // scale y axis
                    1
                );

                o.vertex = mul(UNITY_MATRIX_P, 
                    mul(UNITY_MATRIX_MV, float4(0, 0, 0, 1))
                    + float4(v.vertex.xy, 0, 0)
                    * float4(worldScale, 1));

                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
