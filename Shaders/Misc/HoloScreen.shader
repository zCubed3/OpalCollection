Shader "Opal/HoloScreen"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        [HDR] _Color ("Color", Color) = (1.0, 1.0, 1.0, 1.0)
        
        _SampleCount ("Sample Count", int) = 8
        _Depth ("Depth", float) = -0.1
        _PullDepth ("Pull Depth", float) = 0.1
        _TimeAmplitude ("Time Amplitude", float) = 10
        _UVAmplitude ("UV Amplitude", float) = 10
        _ChromaSize ("Chromatic Scatter", float) = 0.01

        _PixelSize ("Pixel Size", Vector) = (128.0, 128.0, 0.1, 0.0)
        _Scrolling ("UV Scrolling", Vector) = (0.0, 0.0, 0.0, 0.0)
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent-10" }
        LOD 100
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

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
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float3 tangent : TEXCOORD2;
                float3 binormal : TEXCOORD3;
                float3 wPos : TEXCOORD4;
                UNITY_FOG_COORDS(5)

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;

            int _SampleCount;
            float _Depth;
            float _PullDepth;
            float _TimeAmplitude;
            float _UVAmplitude;
            float _ChromaSize;
            float2 _Scrolling;
            float3 _PixelSize;

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v)
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.tangent = UnityObjectToWorldDir(v.tangent);
                o.binormal = cross(o.normal, o.tangent) * v.tangent.w;
                o.wPos = mul(unity_ObjectToWorld, v.vertex);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3x3 tbn = float3x3(
                    normalize(i.tangent),
                    normalize(i.binormal),
                    normalize(i.normal)
                );

                float3 vVec = _WorldSpaceCameraPos - i.wPos;
                float vLen = length(vVec);
                float3 vDir = vVec / vLen;

                float perDepth = _Depth / _SampleCount;

                fixed4 samples = 0; 
                for (int t = 0; t < _SampleCount; t++) {
                    float fakePull = sin(_Time.x * _TimeAmplitude + i.uv.y * _UVAmplitude);
                    fakePull = (fakePull + 1) / 2;
                    fakePull *= _PullDepth;

                    float3 tDir = mul(tbn, vDir * (perDepth * t - fakePull));

                    float2 rawUV = i.uv;
                    float2 uv = frac(rawUV + _Time.xx * _Scrolling);
                    uv += tDir;
                    rawUV += tDir;

                    float2 centerUV = (frac(rawUV * _PixelSize.xy) - 0.5) * 2.0; 

                    float sdf = length(centerUV) - _PixelSize.z;
                    sdf = saturate(sdf);
                    sdf = 1 - sdf;
                    sdf = lerp(sdf, 0.4, saturate(vLen / 0.5));

                    //float2 offset = (uv - 0.5) * 2.0; 
                    float2 offset = float2(1, 0);
                    offset *= _ChromaSize;

                    fixed2 ra = tex2D(_MainTex, uv + offset).ra;
                    fixed2 ga = tex2D(_MainTex, uv).ga;
                    fixed2 ba = tex2D(_MainTex, uv - offset).ba;

                    fixed ta = ra.y + ga.y + ba.y;
                    ta /= 3.0;

                    samples += sdf * fixed4(ra.x, ga.x, ba.x, ta) * _Color;
                }

                fixed4 col = samples / _SampleCount;

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
