using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

namespace Opal
{
    public static class GUIHelpers
    {
        public static bool AskTexture(ref Material material, string property, string name)
        {
            GUILayout.BeginHorizontal();

            GUILayout.Label(name, EditorStyles.boldLabel);
            material.SetTexture(property, EditorGUILayout.ObjectField(material.GetTexture(property), typeof(Texture2D), false) as Texture);

            GUILayout.EndHorizontal();

            return material.GetTexture(property) != null;
        }

        public static bool AskBool(ref Material material, string property, string name)
        {
            GUILayout.BeginHorizontal();

            GUILayout.Label(name, EditorStyles.boldLabel);
            material.SetInt(property, EditorGUILayout.Toggle(material.GetInt(property) != 0) ? 1 : 0);

            GUILayout.EndHorizontal();

            return material.GetInt(property) != 0;
        }

        public static void AskFloat(ref Material material, string property, string name)
        {
            GUILayout.BeginHorizontal();

            GUILayout.Label(name, EditorStyles.boldLabel);
            material.SetFloat(property, EditorGUILayout.FloatField(material.GetFloat(property)));

            GUILayout.EndHorizontal();
        }

        public static void AskFloatRange(ref Material material, string property, string name, float min, float max)
        {
            GUILayout.BeginHorizontal();

            GUILayout.Label(name, EditorStyles.boldLabel);
            material.SetFloat(property, EditorGUILayout.Slider(material.GetFloat(property), min, max));

            GUILayout.EndHorizontal();
        }

        public static void AskColor(ref Material material, string property, string name)
        {
            GUILayout.BeginHorizontal();

            GUILayout.Label(name, EditorStyles.boldLabel);
            material.SetColor(property, EditorGUILayout.ColorField(material.GetColor(property)));

            GUILayout.EndHorizontal();
        }

        public static void AskColorHDR(ref Material material, string property, string name)
        {
            GUILayout.BeginHorizontal();

            GUILayout.Label(name, EditorStyles.boldLabel);
            material.SetColor(property, EditorGUILayout.ColorField(GUIContent.none, material.GetColor(property), true, false, true));

            GUILayout.EndHorizontal();
        }

        public static void AskScaleOffsetInfo(ref Material material, string property, string name)
        {
            GUILayout.Label(name, EditorStyles.boldLabel);

            Vector2 offset = material.GetTextureOffset(property);
            Vector2 scale = material.GetTextureScale(property);

            GUILayout.BeginHorizontal();

            offset.x = EditorGUILayout.FloatField(offset.x);
            offset.y = EditorGUILayout.FloatField(offset.y);
            material.SetTextureOffset(property, offset);

            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();

            scale.x = EditorGUILayout.FloatField(scale.x);
            scale.y = EditorGUILayout.FloatField(scale.y);
            material.SetTextureScale(property, scale);

            GUILayout.EndHorizontal();
        }
    }
}