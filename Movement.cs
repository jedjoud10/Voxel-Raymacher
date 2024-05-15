using OpenTK.Mathematics;
using OpenTK.Windowing.Common;
using OpenTK.Windowing.GraphicsLibraryFramework;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Movement {
        Quaternion rotation;
        public Vector3 position = new Vector3((float)Voxel.size / 2.0f, (float)Voxel.size / 2.0f, (float)Voxel.size / 2.0f);
        public Matrix4 projMatrix;
        public Matrix4 viewMatrix;
        Vector2 mousePosTest;
        bool grabbed = true;

        public void Update(MouseState mouse, KeyboardState keyboard, float ratio, float delta) {
            rotation = Quaternion.FromAxisAngle(Vector3.UnitY, -mousePosTest.X) * Quaternion.FromAxisAngle(Vector3.UnitX, -mousePosTest.Y);

            Vector3 forward = Vector3.Transform(-Vector3.UnitZ, rotation);
            Vector3 up = Vector3.Transform(Vector3.UnitY, rotation);
            Vector3 side = Vector3.Transform(Vector3.UnitX, rotation);

            // Update position and rotation
            float speed = keyboard.IsKeyDown(Keys.LeftControl) ? 5.0f : 30.0f;

            if (keyboard.IsKeyDown(Keys.W)) {
                position += forward * speed * delta;
            } else if (keyboard.IsKeyDown(Keys.S)) {
                position += -forward * speed * delta;
            }

            if (keyboard.IsKeyDown(Keys.A)) {
                position += -side * speed * delta;
            } else if (keyboard.IsKeyDown(Keys.D)) {
                position += side * speed * delta;
            }

            // Create a rotation and position matrix based on current rotation and position
            viewMatrix = Matrix4.CreateFromQuaternion(rotation);
            projMatrix = Matrix4.CreatePerspectiveFieldOfView(MathHelper.DegreesToRadians(70.0f), ratio, 0.1f, 1000.0f);
        }
    }
}
