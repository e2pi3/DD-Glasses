"""공통 전처리. ESP32-S3에서 C로 동일하게 재현 가능한 연산만 사용한다.

보드 파이프라인:
  카메라 QVGA(320x240) GRAYSCALE -> 좌측 240x240 크롭(x=CROP_X0..+240, 우측 80px 제거) -> 3x3 box 평균 -> 80x80
  -> min-max 스트레치(0..255) -> int8 입력 = 값 - 128
"""
from pathlib import Path

import numpy as np
from PIL import Image

IMG_W, IMG_H = 80, 80
IMG_SHAPE = (IMG_H, IMG_W, 1)
# 카메라가 눈보다 살짝 아래에 있어 눈이 (90도 회전된) 프레임 왼쪽으로 치우침 -> 우측을 버린다
CROP_X0 = 0
CLASSES = ["open", "closed"]  # 0: class_1(뜬 눈), 1: class_2(감은 눈)
CLASS_DIRS = {"class_1": 0, "class_2": 1}


def to_qvga_gray(path: Path) -> np.ndarray:
    """800x600 원본을 보드의 QVGA 흑백 프레임과 같은 형태(240x320 uint8)로 만든다."""
    im = Image.open(path).convert("L")  # ITU-R 601 luma = 카메라 Y 채널
    if im.size != (320, 240):
        im = im.resize((320, 240), Image.BOX)
    return np.asarray(im, dtype=np.uint8)


def crop_and_pool(qvga: np.ndarray) -> np.ndarray:
    """x=CROP_X0 부터 240x240 크롭 후 3x3 box 평균으로 80x80 (float32, 0..255).
    (크롭 없이 4x4 평균 80x60 도 시험했으나 배경 영향으로 CV 성능이 더 낮았음)"""
    c = qvga[:, CROP_X0:CROP_X0 + 240].astype(np.float32)
    return c.reshape(IMG_H, 3, IMG_W, 3).mean(axis=(1, 3))


def minmax_stretch(x: np.ndarray) -> np.ndarray:
    """0..1 범위로 스트레치. 보드에서도 같은 식으로 계산한다."""
    lo, hi = float(x.min()), float(x.max())
    return (x - lo) / max(hi - lo, 1.0)


def preprocess(path: Path) -> np.ndarray:
    return minmax_stretch(crop_and_pool(to_qvga_gray(path)))


def list_dataset(root: Path):
    """[(path, label, 파일명 타임스탬프 문자열)] 를 클래스별 시간순으로 반환."""
    items = []
    for d, label in CLASS_DIRS.items():
        for p in sorted((root / d).glob("*.jpg")):
            items.append((p, label, p.stem))
    return items
