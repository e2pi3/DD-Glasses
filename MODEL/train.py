"""눈 뜸/감김 분류기 학습 -> int8 TFLite -> ESP32용 C 배열 생성.

사용법: .venv/Scripts/python train.py
"""
import json
import os
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix

from eye_common import CLASSES, IMG_H, IMG_SHAPE, IMG_W, crop_and_pool, list_dataset, to_qvga_gray

ROOT = Path(__file__).parent
OUT = ROOT / "output"
SEED = 42
N_BLOCKS = 20                 # 클래스별 시간순 연속 블록 수
VAL_BLOCKS = {2, 9, 16}       # 시간축 전체에 퍼지도록 배치
TEST_BLOCKS = {5, 12, 19}
PURGE = 1                     # val/test 블록 경계의 인접 프레임 제거(거의 동일한 프레임 누수 방지)

tf.random.set_seed(SEED)
np.random.seed(SEED)


# ---------------------------------------------------------------- 데이터 분할
def time_block_split(items):
    split = {"train": [], "val": [], "test": []}
    for label in sorted({l for _, l, _ in items}):
        cls = [it for it in items if it[1] == label]
        blocks = np.array_split(np.arange(len(cls)), N_BLOCKS)
        assign = np.empty(len(cls), dtype=object)
        for b, idx in enumerate(blocks):
            assign[idx] = "val" if b in VAL_BLOCKS else "test" if b in TEST_BLOCKS else "train"
        keep = np.ones(len(cls), bool)
        for i in range(len(cls)):
            nb = assign[max(i - PURGE, 0):i + PURGE + 1]
            if assign[i] == "train" and any(n != "train" for n in nb):
                keep[i] = False
        for i, it in enumerate(cls):
            if keep[i]:
                split[assign[i]].append(it)
    return split


def load(items):
    x = np.stack([crop_and_pool(to_qvga_gray(p)) for p, _, _ in items])[..., None]
    y = np.array([l for _, l, _ in items], np.int32)
    return x.astype(np.float32), y  # 0..255 raw (스트레치 전)


# ---------------------------------------------------------------- 증강/정규화
def tf_minmax(x):
    lo = tf.reduce_min(x, axis=[1, 2, 3], keepdims=True)
    hi = tf.reduce_max(x, axis=[1, 2, 3], keepdims=True)
    return (x - lo) / tf.maximum(hi - lo, 1.0)


geo_aug = tf.keras.Sequential([
    tf.keras.layers.RandomFlip("horizontal_and_vertical"),
    tf.keras.layers.RandomRotation(0.06, fill_mode="reflect"),
    tf.keras.layers.RandomTranslation(0.12, 0.12, fill_mode="reflect"),
    tf.keras.layers.RandomZoom((-0.15, 0.15), fill_mode="reflect"),
])


def photometric_aug(x):
    # min-max 로 상쇄되지 않는 비선형 밝기 변화(감마) + 노이즈 + 블러
    n = tf.shape(x)[0]
    x01 = x / 255.0
    gamma = tf.exp(tf.random.uniform([n, 1, 1, 1], -0.5, 0.5))
    x01 = tf.pow(tf.clip_by_value(x01, 1e-4, 1.0), gamma)
    blur = tf.nn.avg_pool2d(x01, 3, 1, "SAME")
    mix = tf.random.uniform([n, 1, 1, 1], 0, 1)
    x01 = mix * blur + (1 - mix) * x01
    x01 += tf.random.normal(tf.shape(x01), stddev=0.02)
    return x01 * 255.0


def make_ds(x, y, train, batch=32):
    ds = tf.data.Dataset.from_tensor_slices((x, y))
    if train:
        ds = ds.shuffle(len(x), seed=SEED, reshuffle_each_iteration=True)
    ds = ds.batch(batch)
    if train:
        ds = ds.map(lambda a, b: (photometric_aug(geo_aug(a, training=True)), b))
    return ds.map(lambda a, b: (tf_minmax(a), b)).prefetch(tf.data.AUTOTUNE)


# ---------------------------------------------------------------- 모델
def ds_block(x, filters, stride, name):
    x = tf.keras.layers.DepthwiseConv2D(3, stride, "same", use_bias=False, name=f"{name}_dw")(x)
    x = tf.keras.layers.BatchNormalization(momentum=0.9, name=f"{name}_dw_bn")(x)
    x = tf.keras.layers.ReLU(6.0, name=f"{name}_dw_relu")(x)
    x = tf.keras.layers.Conv2D(filters, 1, use_bias=False, name=f"{name}_pw")(x)
    x = tf.keras.layers.BatchNormalization(momentum=0.9, name=f"{name}_pw_bn")(x)
    return tf.keras.layers.ReLU(6.0, name=f"{name}_pw_relu")(x)


WIDTH = int(os.environ.get("EYE_WIDTH", "2"))   # 채널 배수. CV(699장)에서 x2 가 x1 보다 오답 절반


def build_model(width=None):
    w = width or WIDTH
    inp = tf.keras.Input(IMG_SHAPE, name="image")
    x = tf.keras.layers.Conv2D(8 * w, 3, 2, "same", use_bias=False, name="stem")(inp)   # 40
    x = tf.keras.layers.BatchNormalization(momentum=0.9, name="stem_bn")(x)
    x = tf.keras.layers.ReLU(6.0, name="stem_relu")(x)
    x = ds_block(x, 16 * w, 2, "b1")   # 20
    x = ds_block(x, 32 * w, 2, "b2")   # 10
    x = ds_block(x, 32 * w, 1, "b3")
    x = ds_block(x, 64 * w, 2, "b4")   # 5
    x = tf.keras.layers.GlobalAveragePooling2D(name="gap")(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    out = tf.keras.layers.Dense(len(CLASSES), activation="softmax", name="probs")(x)
    return tf.keras.Model(inp, out)


# ---------------------------------------------------------------- 평가 유틸
def report(name, y, pred, lines):
    cm = confusion_matrix(y, pred, labels=[0, 1])
    rep = classification_report(y, pred, labels=[0, 1], target_names=CLASSES, digits=3, zero_division=0)
    text = f"=== {name} ===\nconfusion matrix (rows=true {CLASSES}):\n{cm}\n{rep}"
    print(text)
    lines.append(text)


def gradcam_grid(model, x_raw, y, path, n=8):
    conv = model.get_layer("b4_pw_relu").output
    gm = tf.keras.Model(model.input, [conv, model.output])
    rng = np.random.default_rng(SEED)
    idx = np.concatenate([rng.choice(np.where(y == c)[0], min(n // 2, (y == c).sum()), replace=False)
                          for c in (0, 1)])
    x = tf_minmax(tf.constant(x_raw[idx]))
    with tf.GradientTape() as tape:
        f, p = gm(x)
        cls = tf.argmax(p, 1)
        score = tf.gather(p, cls, batch_dims=1)
    g = tape.gradient(score, f)
    w = tf.reduce_mean(g, axis=[1, 2], keepdims=True)
    cam = tf.nn.relu(tf.reduce_sum(w * f, -1, keepdims=True))
    cam = tf.image.resize(cam, (IMG_H, IMG_W)).numpy()[..., 0]
    fig, axes = plt.subplots(2, len(idx) // 2 + len(idx) % 2, figsize=(2.2 * len(idx) / 2, 4.6))
    for ax, i in zip(axes.ravel(), range(len(idx))):
        ax.imshow(x[i, ..., 0], cmap="gray")
        c = cam[i] / (cam[i].max() + 1e-8)
        ax.imshow(c, cmap="jet", alpha=0.4)
        ax.set_title(f"T:{CLASSES[y[idx[i]]]} P:{CLASSES[int(cls[i])]}", fontsize=8)
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def write_c_array(tflite_bytes, path_h):
    """Arduino 스케치 폴더에 그대로 넣을 수 있는 단일 헤더(.ino 에서 한 번만 include)."""
    hexes = ",".join(f"0x{b:02x}" if i % 16 else f"\n  0x{b:02x}" for i, b in enumerate(tflite_bytes))
    path_h.write_text(
        "// 자동 생성 파일 (train.py). 직접 수정하지 말 것.\n"
        "#pragma once\n\n"
        "alignas(16) const unsigned char g_eye_model[] = {" + hexes + "\n};\n"
        f"const unsigned int g_eye_model_len = {len(tflite_bytes)};\n", encoding="utf-8")


# ---------------------------------------------------------------- main
def main():
    OUT.mkdir(exist_ok=True)
    split = time_block_split(list_dataset(ROOT))
    for k, v in split.items():
        ys = [l for _, l, _ in v]
        print(f"{k:5s}: {len(v):3d}  open={ys.count(0)} closed={ys.count(1)}")
    (OUT / "split.json").write_text(json.dumps(
        {k: [str(p.relative_to(ROOT)) for p, _, _ in v] for k, v in split.items()}, indent=1))

    xtr, ytr = load(split["train"])
    xva, yva = load(split["val"])
    xte, yte = load(split["test"])

    counts = np.bincount(ytr, minlength=2)
    class_weight = {i: len(ytr) / (2 * c) for i, c in enumerate(counts)}
    print("class_weight:", class_weight)

    model = build_model()
    model.summary()
    model.compile(tf.keras.optimizers.Adam(2e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    hist = model.fit(
        make_ds(xtr, ytr, True), validation_data=make_ds(xva, yva, False),
        epochs=150, class_weight=class_weight, verbose=2,
        callbacks=[
            tf.keras.callbacks.EarlyStopping("val_loss", patience=30, restore_best_weights=True),
            tf.keras.callbacks.ReduceLROnPlateau("val_loss", factor=0.5, patience=10, min_lr=1e-5),
        ])
    model.save(OUT / "eye_model.keras")

    plt.figure(figsize=(8, 3))
    for i, m in enumerate(["loss", "accuracy"]):
        plt.subplot(1, 2, i + 1)
        plt.plot(hist.history[m], label="train")
        plt.plot(hist.history[f"val_{m}"], label="val")
        plt.title(m); plt.legend()
    plt.tight_layout(); plt.savefig(OUT / "history.png", dpi=110); plt.close()

    lines = []
    for name, x, y in [("val (float)", xva, yva), ("test (float)", xte, yte)]:
        pred = model.predict(tf_minmax(tf.constant(x)), verbose=0).argmax(1)
        report(name, y, pred, lines)

    # ---- int8 전정수 양자화
    xtr01 = tf_minmax(tf.constant(xtr)).numpy()

    def rep_data():
        for i in range(len(xtr01)):
            yield [xtr01[i:i + 1]]

    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    conv.representative_dataset = rep_data
    conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    conv.inference_input_type = tf.int8
    conv.inference_output_type = tf.int8
    tfl = conv.convert()
    (OUT / "eye_model_int8.tflite").write_bytes(tfl)

    interp = tf.lite.Interpreter(model_content=tfl)
    interp.allocate_tensors()
    ind, outd = interp.get_input_details()[0], interp.get_output_details()[0]
    in_s, in_z = ind["quantization"]
    print(f"int8 input quant: scale={in_s:.8f} zero_point={in_z}  (기대값 1/255, -128)")
    xte01 = tf_minmax(tf.constant(xte)).numpy()
    preds = []
    for i in range(len(xte01)):
        q = np.clip(np.round(xte01[i:i + 1] / in_s + in_z), -128, 127).astype(np.int8)
        interp.set_tensor(ind["index"], q)
        interp.invoke()
        preds.append(interp.get_tensor(outd["index"])[0].argmax())
    report("test (int8 tflite)", yte, np.array(preds), lines)

    ops = sorted({d["op_name"] for d in interp._get_ops_details()})
    info = (f"tflite size: {len(tfl)} bytes\nops: {ops}\n"
            f"input quant: scale={in_s} zero_point={in_z}\n"
            f"output quant: {outd['quantization']}\n")
    print(info)
    lines.append(info)
    (OUT / "report.txt").write_text("\n".join(lines), encoding="utf-8")

    write_c_array(tfl, OUT / "eye_model_data.h")
    gradcam_grid(model, xte, yte, OUT / "gradcam_test.png")
    print("saved to", OUT)


if __name__ == "__main__":
    main()
