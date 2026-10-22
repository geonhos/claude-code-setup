# 다이어그램

`.mmd` 파일이 원본이고, `.svg`는 `.mmd`에서 렌더링해 [`../architecture.md`](../architecture.md)에 넣은 것이다.
하나만 다시 렌더링하려면 `mmdc -i X.mmd -o X.svg --backgroundColor white`,
전부 하려면 `for f in *.mmd; do mmdc -i $f -o ${f%.mmd}.svg --backgroundColor white; done`을 실행한다.
그다음 `architecture.md`의 해당 Mermaid 블록도 같이 고친다.

- [2026-10-22 구조 리뷰 도식](2026-10-22-structure-review/README.md): 업무 지시 흐름, 워커 실행/exit code, 훅, 리뷰
