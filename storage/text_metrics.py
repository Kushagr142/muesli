def count_words(text: str) -> int:
    compact = " ".join((text or "").split())
    if not compact:
        return 0
    return len(compact.split(" "))
