from PIL import Image, ImageOps

def invert_logo():
    img = Image.open('assets/logo_master.png').convert('RGBA')
    
    r, g, b, a = img.split()
    rgb_image = Image.merge('RGB', (r, g, b))
    
    inverted_image = ImageOps.invert(rgb_image)
    r2, g2, b2 = inverted_image.split()
    
    final_transparent_image = Image.merge('RGBA', (r2, g2, b2, a))
    
    final_transparent_image.save('assets/logo_master_inverted.png')
    print("Successfully created logo_master_inverted.png")

if __name__ == '__main__':
    invert_logo()
