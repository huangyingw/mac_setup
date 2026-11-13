#!/usr/bin/env python3
"""把 voice_input 仓库导出的 Spokenly 设置写进 Spokenly 的设置文件，或核对两者是否一致。

  settings.py apply <设置文件.plist> <设置.json>...   写入（后面的 json 盖前面的；设置文件里已有的其它键保留）
  settings.py check <设置文件.plist> <设置.json>...   只比较；有不一致的键就列出来，退出码 1

设置 json 的格式由 voice_input 的 service/spokenly-settings.py 定：Spokenly 把多数设置
「JSON 编码后存成 Data」，导出时写成 {"__json__": ...}，这里写回去时再编码成 Data。
那个脚本按电脑名挑覆盖文件，对方的电脑叫什么事先不知道，所以这里改成由调用方点名用哪几个文件。
"""
import json
import os
import plistlib
import sys

# 「已经走完首次启动向导」的标记。voice_input 把它们算作各机状态、不导出；
# 目标机是全新安装，不写的话 Spokenly 会弹向导，向导里选的快捷键和模型会盖掉我们写的设置。
# 取值与参考机一致。
ONBOARDED = {
    'hasCompletedOnboarding': True,
    'onboarding.didClickFinish': True,
    'isFirstLaunch': False,
    'currentStep': 3,
}


def wanted(files):
    out = {}
    for path in files:
        with open(path) as f:
            out.update(json.load(f))
    out.update(ONBOARDED)
    return out


def encode(v):
    if isinstance(v, dict) and '__json__' in v:
        return json.dumps(v['__json__'], ensure_ascii=False, separators=(',', ':')).encode()
    return v


def comparable(v):
    """转成可比较的形式。Data 解回 JSON；updatedAt 是 Spokenly 自己会刷新的时间戳，不参与比较。"""
    if isinstance(v, dict) and '__json__' in v:
        v = v['__json__']
    elif isinstance(v, bytes):
        try:
            v = json.loads(v)
        except ValueError:
            return repr(v)
    return strip_stamps(v)


def strip_stamps(v):
    if isinstance(v, dict):
        return {k: strip_stamps(x) for k, x in v.items() if k != 'updatedAt'}
    if isinstance(v, list):
        return [strip_stamps(x) for x in v]
    return v


def load(plist):
    if not os.path.exists(plist):
        return {}
    with open(plist, 'rb') as f:
        return plistlib.load(f)


def main(argv):
    if len(argv) < 4 or argv[1] not in ('apply', 'check'):
        sys.exit(__doc__)
    cmd, plist, files = argv[1], argv[2], argv[3:]
    want = wanted(files)
    data = load(plist)
    if cmd == 'apply':
        data.update({k: encode(v) for k, v in want.items()})
        os.makedirs(os.path.dirname(plist), exist_ok=True)
        fd = os.open(plist, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'wb') as f:
            plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
        print('已写入 %d 项设置' % len(want))
        return 0
    bad = [k for k in sorted(want) if k not in data or comparable(data[k]) != comparable(want[k])]
    for k in bad:
        print('不一致: %s' % k)
        print('    应为: %s' % json.dumps(comparable(want[k]), ensure_ascii=False)[:300])
        print('    实际: %s' % (json.dumps(comparable(data[k]), ensure_ascii=False)[:300] if k in data else '（没有这一项）'))
    if not bad:
        print('%d 项设置全部一致' % len(want))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
