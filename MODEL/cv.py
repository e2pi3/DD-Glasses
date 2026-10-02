"""시간 블록 기반 5-fold 교차검증 + '감은 눈' 판정 임계값 분석.

각 클래스를 시간순 연속 블록 5개로 나누고, 블록 하나씩을 검증에 쓴다.
검증 블록 경계의 인접 프레임은 학습에서 제외(누수 방지).
"""
import numpy as np
import tensorflow as tf
from sklearn.metrics import confusion_matrix

import train as T
from eye_common import list_dataset

K = 5
TH = [0.2, 0.3, 0.4, 0.5, 0.6]


def fold_split(items, k):
    tr, va = [], []
    for label in (0, 1):
        cls = [it for it in items if it[1] == label]
        blocks = np.array_split(np.arange(len(cls)), K)
        vset = set(blocks[k].tolist())
        for i, it in enumerate(cls):
            if i in vset:
                va.append(it)
            elif all(j not in vset for j in range(i - T.PURGE, i + T.PURGE + 1)):
                tr.append(it)
    return tr, va


def main():
    items = list_dataset(T.ROOT)
    all_y, all_p = [], []
    for k in range(K):
        tf.keras.backend.clear_session()
        tf.random.set_seed(T.SEED + k)
        tr, va = fold_split(items, k)
        xtr, ytr = T.load(tr)
        xva, yva = T.load(va)
        cnt = np.bincount(ytr, minlength=2)
        cw = {i: len(ytr) / (2 * c) for i, c in enumerate(cnt)}
        m = T.build_model()
        m.compile(tf.keras.optimizers.Adam(2e-3), "sparse_categorical_crossentropy", ["accuracy"])
        # 검증 블록을 early stopping에 쓰면 낙관적이 되므로 고정 epoch 학습
        m.fit(T.make_ds(xtr, ytr, True), epochs=60, class_weight=cw, verbose=0,
              callbacks=[tf.keras.callbacks.LearningRateScheduler(
                  lambda e: 2e-3 * 0.5 * (1 + np.cos(np.pi * e / 60)))])
        p = m.predict(T.tf_minmax(tf.constant(xva)), verbose=0)[:, 1]
        pred = (p >= 0.5).astype(int)
        cm = confusion_matrix(yva, pred, labels=[0, 1])
        print(f"fold {k}: n={len(yva)} closed={int(yva.sum())}  cm={cm.tolist()}")
        all_y.append(yva); all_p.append(p)

    y = np.concatenate(all_y); p = np.concatenate(all_p)
    print(f"\n=== pooled ({len(y)} imgs, closed={int(y.sum())}) ===")
    print(" th   acc    open_recall  closed_recall  closed_precision")
    for th in TH:
        pr = (p >= th).astype(int)
        tn, fp, fn, tp = confusion_matrix(y, pr, labels=[0, 1]).ravel()
        print(f"{th:.1f}  {(tp + tn) / len(y):.3f}   {tn / (tn + fp):.3f}        "
              f"{tp / (tp + fn):.3f}          {tp / max(tp + fp, 1):.3f}")


if __name__ == "__main__":
    main()
