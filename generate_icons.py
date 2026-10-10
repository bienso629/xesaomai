import os
from PIL import Image

src_img = "/home/yenai/Documents/Projects/Taxi/docs/app.jpeg"
im = Image.open(src_img).convert("RGBA")

# Android mipmap icons
android_res = "/home/yenai/Documents/Projects/Taxi/app_tai_xe/android/app/src/main/res"
android_sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

for folder, size in android_sizes.items():
    folder_path = os.path.join(android_res, folder)
    os.makedirs(folder_path, exist_ok=True)
    out_file = os.path.join(folder_path, "ic_launcher.png")
    resized = im.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(out_file, "PNG")
    print(f"Generated Android: {out_file} ({size}x{size})")

# Web icons
web_icons_dir = "/home/yenai/Documents/Projects/Taxi/app_tai_xe/web/icons"
os.makedirs(web_icons_dir, exist_ok=True)
im.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-192.png"), "PNG")
im.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-512.png"), "PNG")
im.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-maskable-192.png"), "PNG")
im.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(web_icons_dir, "Icon-maskable-512.png"), "PNG")
im.resize((64, 64), Image.Resampling.LANCZOS).save("/home/yenai/Documents/Projects/Taxi/app_tai_xe/web/favicon.png", "PNG")
print("Generated Web icons & favicon")

# Linux app icon
linux_assets_dir = "/home/yenai/Documents/Projects/Taxi/app_tai_xe/linux/assets"
os.makedirs(linux_assets_dir, exist_ok=True)
im.resize((256, 256), Image.Resampling.LANCZOS).save(os.path.join(linux_assets_dir, "app_icon.png"), "PNG")
print("Generated Linux app icon: linux/assets/app_icon.png")

# Flutter assets
flutter_assets_dir = "/home/yenai/Documents/Projects/Taxi/app_tai_xe/assets/images"
os.makedirs(flutter_assets_dir, exist_ok=True)
im.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(flutter_assets_dir, "app_icon.png"), "PNG")
print("Generated Flutter asset: assets/images/app_icon.png")
