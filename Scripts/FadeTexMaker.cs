//
// FadeTexMaker.cs - This script provides a tool that lets you bake Unity gradients into textures!
//

using System.Collections;
using System.Collections.Generic;
using System.IO;

using UnityEngine;
using UnityEditor;

public class FadeTexMaker : EditorWindow {
    [MenuItem("zCubed/Tools/Fade Tex Maker")]
    static void Init() {
        FadeTexMaker window = EditorWindow.GetWindow<FadeTexMaker>();
        window.Show();
    }

    Gradient gradient = new Gradient();
    int width = 256;
    int height = 2;

    private void OnGUI(){
        gradient = EditorGUILayout.GradientField("Gradient", gradient);
        width = EditorGUILayout.IntField("Output Width", width);
        height = EditorGUILayout.IntField("Output Height", height);

        if (GUILayout.Button("Save Texture")) {
            Texture2D texture = new Texture2D(width, height, TextureFormat.ARGB32, true);

            for (int x = 0; x < width; x++) {
                Color color = gradient.Evaluate(x / (float)width);
                for (int y = 0; y < height; y++) {
                    texture.SetPixel(x, y, color);
                }
            }

            texture.Apply();
            byte[] pixels = texture.EncodeToPNG();

            string path = EditorUtility.SaveFilePanel("Save Image", "", "", "png");

            File.WriteAllBytes(path, pixels);

            string relative = "Assets" + path.Replace(Application.dataPath, "");
            AssetDatabase.ImportAsset(relative);
        }
    }
}
