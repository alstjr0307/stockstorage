"""Pretendard 원본(tools/fonts_source) → 웹/앱 번들용 서브셋(assets/fonts).

Flutter 웹은 pubspec 에 선언한 폰트를 시작할 때 전부 내려받는다. 원본 5종은
압축 후에도 4.4MB 라 첫 로딩의 대부분을 차지해서, 실제로 쓰는 문자만 남긴다.

남기는 범위:
  - KS X 1001 한글 음절 2,350자 (실사용 한국어 거의 전부)
  - 한글 자모, 라틴/숫자/문장부호, 통화·화살표·도형 등 UI 기호
빠진 희귀 음절은 CanvasKit 이 Noto 폴백을 받아 대신 그린다.

사용법: python tools/subset_fonts.py
"""

import pathlib
import subprocess
import sys

SOURCE_DIR = pathlib.Path(__file__).parent / "fonts_source"
OUTPUT_DIR = pathlib.Path(__file__).parent.parent / "assets" / "fonts"

# 문자 그대로 유지할 유니코드 구간
UNICODE_RANGES = [
    "U+0020-007E",  # 기본 라틴
    "U+00A0-00FF",  # 라틴-1 보충
    "U+0100-017F",  # 라틴 확장-A
    "U+02B0-02FF",  # 수정 문자
    "U+1100-11FF",  # 한글 자모
    "U+2000-206F",  # 일반 문장부호
    "U+2070-209F",  # 위/아래 첨자
    "U+20A0-20BF",  # 통화 기호
    "U+2100-214F",  # 문자꼴 기호
    "U+2190-21FF",  # 화살표
    "U+2200-22FF",  # 수학 연산자
    "U+2460-24FF",  # 원문자
    "U+25A0-25FF",  # 도형
    "U+2600-26FF",  # 기타 기호
    "U+3000-303F",  # CJK 문장부호
    "U+3130-318F",  # 한글 호환 자모
    "U+FF00-FFEF",  # 전각 형태
]


def ks_x_1001_syllables() -> str:
    """KS X 1001 완성형 2,350자.

    파이썬 euc-kr 코덱은 UHC 확장까지 받아줘서 11,172자가 모두 통과한다.
    KS X 1001 본체는 두 바이트가 모두 0xA1-0xFE 인 것만 해당한다.
    """
    out = []
    for code in range(0xAC00, 0xD7A4):
        char = chr(code)
        try:
            encoded = char.encode("euc-kr")
        except UnicodeEncodeError:
            continue
        if len(encoded) == 2 and all(0xA1 <= b <= 0xFE for b in encoded):
            out.append(char)
    return "".join(out)


def subset(source: pathlib.Path, syllables: str) -> None:
    target = OUTPUT_DIR / source.name
    subprocess.run(
        [
            sys.executable,
            "-m",
            "fontTools.subset",
            str(source),
            f"--output-file={target}",
            f"--unicodes={','.join(UNICODE_RANGES)}",
            f"--text={syllables}",
            "--layout-features=kern,liga,calt",
            "--drop-tables+=post",
            "--no-hinting",
            "--desubroutinize",
        ],
        check=True,
    )
    before = source.stat().st_size / 1024
    after = target.stat().st_size / 1024
    print(f"{source.name}: {before:,.0f} KB → {after:,.0f} KB")


def main() -> None:
    sources = sorted(SOURCE_DIR.glob("*.ttf"))
    if not sources:
        sys.exit(f"원본 폰트가 없습니다: {SOURCE_DIR}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    syllables = ks_x_1001_syllables()
    print(f"한글 음절 {len(syllables)}자 + 기호 구간 유지")
    for source in sources:
        subset(source, syllables)


if __name__ == "__main__":
    main()
