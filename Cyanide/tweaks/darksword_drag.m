//
//  darksword_drag.m
//
//  Adapted from kolbicz/DarkSword-Tweaks override_drag_coefficient.m.
//

#import "darksword_drag.h"
#import "../TaskRop/RemoteCall.h"

#import <dlfcn.h>
#import <stdint.h>
#import <stdbool.h>
#import <stdio.h>

typedef struct {
    uint64_t g;
    uint64_t revVar;
    uint64_t revOnce;
    uint32_t valOff;
    uint32_t revOff;
} drag_t;

static uint64_t drag_strip_fp(void *p)
{
    uint64_t v = (uint64_t)p;
#if __has_feature(ptrauth_calls)
    if (v >> 47) {
        v = (uint64_t)__builtin_ptrauth_strip((void *)v, 0);
    }
#endif
    return v;
}

static bool drag_find(drag_t *out)
{
    if (!out) return false;

    void *fp = dlsym(RTLD_DEFAULT, "_SetUIAnimationDragCoefficient");
    if (!fp) {
        printf("[DRAG] _SetUIAnimationDragCoefficient not found\n");
        return false;
    }

    uint64_t pc = drag_strip_fp(fp);
    const uint32_t *code = (const uint32_t *)pc;

    // Follow a small B/BL thunk if dyld exposes one instead of the real body.
    for (int i = 0; i < 4; i++) {
        if ((code[i] & 0xfc000000) == 0x14000000) {
            pc += (uint64_t)i * 4 + (int64_t)((int32_t)(code[i] << 6) >> 4);
            code = (const uint32_t *)pc;
            break;
        }
    }

    uint64_t page[32] = {0};
    uint64_t ptr[32] = {0};
    uint64_t g = 0;
    uint64_t revVar = 0;
    uint64_t revOnce = 0;
    uint32_t valOff = 0;
    uint32_t revOff = 0;

    for (int i = 0; i < 80; i++) {
        uint32_t insn = code[i];
        int rd = insn & 31;
        int rn = (insn >> 5) & 31;
        uint64_t ipc = pc + (uint64_t)i * 4;

        if ((insn & 0x9f000000) == 0x90000000) {
            int64_t lo = (insn >> 29) & 3;
            int64_t hi = (insn >> 5) & 0x7ffff;
            int64_t off = ((hi << 2) | lo) << 12;
            off = (off << 31) >> 31;
            page[rd] = (ipc & ~0xfffULL) + off;
            ptr[rd] = 0;
        } else if ((insn & 0xff800000) == 0x91000000 && page[rn]) {
            ptr[rd] = page[rn] + ((insn >> 10) & 0xfff);
        } else if ((insn & 0xffc00000) == 0xf9400000 && page[rn] && !revOnce) {
            revOnce = page[rn] + (((insn >> 10) & 0xfff) << 3);
        } else if ((insn & 0xffc00000) == 0xb9400000 && page[rn] && !revVar) {
            revVar = page[rn] + (((insn >> 10) & 0xfff) << 2);
        } else if ((insn & 0xff800000) == 0xfd000000 && ptr[rn] && !g) {
            g = ptr[rn];
            valOff = ((insn >> 10) & 0xfff) << 3;
        } else if ((insn & 0xff800000) == 0xb9000000 && g && ptr[rn] == g) {
            revOff = ((insn >> 10) & 0xfff) << 2;
            break;
        }
    }

    if (!g || !revVar || !revOnce ||
        (revOnce != revVar + 8 && revVar != revOnce + 8)) {
        return false;
    }

    out->g = g;
    out->revVar = revVar;
    out->revOnce = revOnce;
    out->valOff = valOff ? valOff : 8;
    out->revOff = revOff;
    return true;
}

bool darksword_drag_coefficient_apply(double coefficient)
{
    if (coefficient < 0.05) coefficient = 0.05;
    if (coefficient > 2.0) coefficient = 2.0;

    drag_t d = {0};
    if (!drag_find(&d)) {
        printf("[DRAG] find failed\n");
        return false;
    }

    uint32_t revision = 0;
    remote_read(d.revVar, &revision, sizeof(revision));
    if ((int)revision < 1) {
        uint32_t one = 1;
        remote_write(d.revVar, &one, sizeof(one));
        revision = 1;
    }

    union { double value; uint64_t raw; } bits = { .value = coefficient };
    uint32_t sentinel = 0x7fffffff;

    remote_write(d.g + d.revOff, &sentinel, sizeof(sentinel));
    remote_write(d.g + d.valOff, &bits.raw, sizeof(bits.raw));

    double checkValue = 0.0;
    uint32_t checkRev = 0;
    remote_read(d.g + d.valOff, &checkValue, sizeof(checkValue));
    remote_read(d.g + d.revOff, &checkRev, sizeof(checkRev));
    printf("[DRAG] g=0x%llx revVar=%u value=%.4f slotRev=0x%x\n",
           (unsigned long long)d.g,
           revision,
           checkValue,
           checkRev);
    return true;
}
