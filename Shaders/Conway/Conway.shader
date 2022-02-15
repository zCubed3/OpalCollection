Shader "Opal/Conway/Simulator"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _TickInterval ("TickInterval", float) = 0.5
        [Toggle] _KillEdge ("Kill At Edge", int) = 1
        _KillEdgeThreshold ("Edge Threshold", float) = 0.01
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;
            float _TickInterval, _KillEdgeThreshold;
            int _KillEdge;

            v2f vert (appdata v)
            {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;

                return o;
            }

            float2 frag (v2f i) : SV_Target
            {
                float3 offset = float3(_MainTex_TexelSize.xy, 0);

                float2 info = tex2D(_MainTex, i.uv).rg;
                info.g += unity_DeltaTime;

                if (info.g <= _TickInterval)
                    return info.rg;
                else
                    info.g = 0;

                const float lowerBound = 2.0 / 8; 
                const float upperBound = 3.0 / 8; 
                const float2 signs = float2(1, -1);
                
                float biases =
                    tex2D(_MainTex, i.uv + offset.xz).r + // Left
                    tex2D(_MainTex, i.uv - offset.xz).r + // Right
                    tex2D(_MainTex, i.uv + offset.zy).r + // Up
                    tex2D(_MainTex, i.uv - offset.zy).r + // Down
                    tex2D(_MainTex, i.uv + offset.xy * signs.xx).r + // Upper Right
                    tex2D(_MainTex, i.uv + offset.xy * signs.yy).r + // Lower Left
                    tex2D(_MainTex, i.uv + offset.xy * signs.yx).r + // Lower Right 
                    tex2D(_MainTex, i.uv + offset.xy * signs.xy).r; // Upper Left

                biases /= 8.0;

                float live = 0;

                if (info.r == 0)
                    live = biases == upperBound;
                else
                    live = biases >= lowerBound && biases <= upperBound;

                if (_KillEdge == 1 && live == 1)
                    live = i.uv.x >= _KillEdgeThreshold && i.uv.x <= (1 - _KillEdgeThreshold)
                        && i.uv.y >= _KillEdgeThreshold && i.uv.y <= (1 - _KillEdgeThreshold);

                return float2(live, 0);
            }
            ENDHLSL
        }
    }
}
