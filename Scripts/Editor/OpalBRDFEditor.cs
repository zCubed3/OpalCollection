using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

namespace Opal
{
    public class OpalBRDFEditor : ShaderGUI
    {
        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
        {
            //base.OnGUI(materialEditor, properties);

            GUILayout.Label("Opal BRDF", EditorStyles.boldLabel);
        }
    }
}