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
    }
}