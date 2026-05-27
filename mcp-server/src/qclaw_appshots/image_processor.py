"""
Image processing utilities.

- Resize base64-encoded images for LLM consumption
- Keep aspect ratio, limit max width/height
"""

from __future__ import annotations

import base64
import io


class ImageProcessor:
    """Process screenshots before sending to LLMs."""

    MAX_WIDTH = 2048
    MAX_HEIGHT = 2048
    JPEG_QUALITY = 85

    @classmethod
    def resize_base64(
        cls,
        image_base64: str,
        max_width: int | None = None,
        max_height: int | None = None,
    ) -> str:
        """Resize a base64-encoded PNG/JPEG and return as base64 JPEG.

        Args:
            image_base64: Base64-encoded image data
            max_width: Maximum width in pixels (default 2048)
            max_height: Maximum height in pixels (default 2048)

        Returns:
            Base64-encoded resized JPEG
        """
        try:
            from PIL import Image
        except ImportError:
            # Pillow not available, return original
            return image_base64

        max_w = max_width or cls.MAX_WIDTH
        max_h = max_height or cls.MAX_HEIGHT

        img_data = base64.b64decode(image_base64)
        img = Image.open(io.BytesIO(img_data))

        # Only resize if image is larger than max dimensions
        if img.width > max_w or img.height > max_h:
            ratio = min(max_w / img.width, max_h / img.height)
            new_size = (int(img.width * ratio), int(img.height * ratio))
            img = img.resize(new_size, Image.Resampling.LANCZOS)

        # Convert to JPEG for smaller size
        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="JPEG", quality=cls.JPEG_QUALITY)
        return base64.b64encode(buf.getvalue()).decode("ascii")
