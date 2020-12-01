using UnityEngine;

public class ContainerVisualizer : MonoBehaviour {

    public Color colour = Color.green;
    public bool displayOutline = true;

    void OnDrawGizmos() {
        if (displayOutline) {
            Gizmos.color = colour;
            Gizmos.DrawWireCube (transform.position, transform.localScale);
        }
    }
}