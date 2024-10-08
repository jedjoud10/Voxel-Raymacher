﻿using OpenTK.Mathematics;
using OpenTK.Windowing.Common;
using OpenTK.Windowing.GraphicsLibraryFramework;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Test123Bruh {
    internal class Movement {
        Quaternion rotation = Quaternion.Identity;
        public float smoothing = 10.0f;
        public float hFov = 60.0f;
        public Vector3 position = new Vector3((float)Voxel.MapSize / 2.0f, (float)Voxel.MapSize / 2.0f, (float)Voxel.MapSize / 2.0f);
        public Matrix4 projMatrix;
        public Matrix4 viewMatrix;
        Vector3 lastVelocity;
        Vector2 mousePosTest;
        Vector3 forward;
        Vector3 side;
        Vector3 up;
        Random rng = new Random();

        float nfmod(float a, float b) {
            return a - b * MathF.Floor(a / b);
        }

        // Moves the player position and handles rotation
        public void Move(MouseState mouse, KeyboardState keyboard, float delta) {
            //mousePosTest += Vector2.Clamp(mouse.Delta, -Vector2.One * 200, Vector2.One * 200) * 0.0005f;
            mousePosTest += mouse.Delta * 0.0005f;
            Quaternion newRotation = Quaternion.FromAxisAngle(Vector3.UnitY, -mousePosTest.X) * Quaternion.FromAxisAngle(Vector3.UnitX, -mousePosTest.Y);
            rotation = Quaternion.Slerp(rotation, newRotation, MathHelper.Clamp(smoothing * delta * 5, 0f, 1f));

            forward = Vector3.Transform(-Vector3.UnitZ, rotation);
            side = Vector3.Transform(Vector3.UnitX, rotation);
            up = Vector3.Transform(Vector3.UnitY, rotation);

            // Update position and rotation
            float speed = keyboard.IsKeyDown(Keys.LeftControl) ? 1.0f : 30.0f;
            Vector3 velocity = Vector3.Zero;

            if (keyboard.IsKeyDown(Keys.W)) {
                velocity += forward;
            } else if (keyboard.IsKeyDown(Keys.S)) {
                velocity += -forward;
            }

            if (keyboard.IsKeyDown(Keys.A)) {
                velocity += -side;
            } else if (keyboard.IsKeyDown(Keys.D)) {
                velocity += side;
            }

            lastVelocity = Vector3.Lerp(lastVelocity, velocity * speed, MathHelper.Clamp(delta * smoothing, 0f, 1f));
            position += lastVelocity * delta;

            position.X = nfmod(position.X, (float)Voxel.MapSize);
            position.Y = nfmod(position.Y, (float)Voxel.MapSize);
            position.Z = nfmod(position.Z, (float)Voxel.MapSize);
        }

        // Create a rotation and position matrix based on current rotation and position
        public void UpdateMatrices(float ratio, bool rando) {
            Quaternion randoRot = rando ? Quaternion.FromEulerAngles(rng.NextSingle() * 0.001f, rng.NextSingle() * 0.001f, 0.0f) : Quaternion.Identity;
            viewMatrix = Matrix4.CreateFromQuaternion(rotation) * Matrix4.CreateTranslation(position);
            //viewMatrix = Matrix4.LookAt(position, position + forward, -up);

            float yFov = 2.0f * MathF.Atan(MathF.Tan(MathHelper.DegreesToRadians(hFov) / 2.0f) * (1.0f/ratio));
            projMatrix = Matrix4.CreatePerspectiveFieldOfView(MathHelper.Clamp(yFov, 0.001f, 1.99f * MathF.PI), 1.0f/ratio, 1.0f, 100.0f);
        }
    }
}
