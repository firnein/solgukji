"""motion.5 역할 점검 JSON을 표와 원본 요약으로 정리한다."""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "build/motion5_role_audit.json"
DEST = ROOT / "docs/benchmarks/motion5_role_audit.json"
DOCUMENT = ROOT / "docs/전투_역할_점검_motion5.md"
DAMAGE = ("basic", "minor", "skill", "ultimate", "counter", "other")


def mean(rows: list[dict], key: str) -> float:
    return sum(float(row[key]) for row in rows) / len(rows)


def main() -> None:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    trials = int(data["trials"])
    assert trials > 0 and len(data["zhou_yu_runs"]) == trials * 16
    roles: dict[tuple, list] = defaultdict(list)
    commanders: dict[tuple, list] = defaultdict(list)
    for battle in data["role_runs"]:
        assert len(battle["units"]) == 9
        for row in battle["units"]:
            assert all(float(row[key]) >= 0 for key in DAMAGE)
            if not battle["ultimates"]:
                assert row["ultimate"] == 0 and row["ults"] == 0
            roles[(battle["tier"], battle["ultimates"], row["tag"])].append(row)
    for row in data["zhou_yu_runs"]:
        commanders[(row["name"], row["slot"])].append(row)
        assert row["ults"] == 0, "이 비교의 전설 책사들은 고유기 없이 기여해야 한다"
    lines = [
        "# motion.5 원거리·기병 및 전설 주유 역할 점검", "",
        "2026-11-17 / Godot " + data["engine"] + ". 수치 변경 없이 현재 엔진을 측정했다.", "",
        "## 측정 방식", "",
        "- 역할 비교: 전설·불멸·신화별 동일 무작위 9대9 편성 12개를 고유기 켬/끔, 양쪽 진영으로 반복했다. 총 144전투다.",
        "- 주유 비교: 전설 일반 책사 주유·종회·육손·강유를 같은 8명 팀원과 같은 상대에 하나씩 넣는다. 어림진의 앞쪽 1번/뒤쪽 7번, 12시드, 양 진영으로 총 192전투다. 후보 인물은 팀원/상대에서 제외한다.",
        "- seed: 역할 65100~65111, 주유 75100~75111. 무작위 편성 생성기도 고정했다.",
        "- 평타·잔기술·일반 기술·고유기·반격·기타 직접 피해를 실행 경로로 구분했다. 직접 피해는 초과 피해를 제외한 주대상 손실이며 분담 피해는 포함하지 않는다. 지속 피해는 기존 엔진의 실제 DOT 기여 집계다.",
        "- 병력 회복은 엔진의 최대 병력 대비 회복 비율, 지원은 기존 갑옷/결계 약화 기여 집계다. 둘을 직접 피해와 합산해 순위를 만들지 않았다.",
        "- 계측기 사용 전/후 사건 JSON·승패·잔존 부대가 같은지 별도로 검사했다.", "",
        "## 전설 주유: 역할은 존재하며, 출처 표시가 빠져 있었다", "",
        "주유는 고유기 없이 평타·잔기술·화상으로 기여했다. 이 편성의 교체 비교에서 기여가 없다는 가설은 확인되지 않았다. 이 결과만으로 모든 덱에서의 적정 승률을 확정하지 않으며 공격력이나 확률을 올리지 않았다.", "",
        "| 장수 | 자리 | 표본 | 평타 | 잔기술 | 일반 기술 | 지속 피해 | 평균 행동 | 승/무/패 |",
        "|---|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for (name, slot), rows in commanders.items():
        assert len(rows) == trials * 2
        wins = sum(row["win"] for row in rows)
        draws = sum(row["draw"] for row in rows)
        lines.append(
            f"| {name} | {'앞 1번' if slot == 1 else '뒤 7번'} | {len(rows)} | "
            f"{mean(rows, 'basic'):,.0f} | {mean(rows, 'minor'):,.0f} | {mean(rows, 'skill'):,.0f} | "
            f"{mean(rows, 'dot'):,.0f} | {mean(rows, 'actions'):.1f} | {wins}/{draws}/{len(rows)-wins-draws} |"
        )
    lines += [
        "", "표본 24는 독립적인 상대 24개를 뜻하지 않는다. 같은 12개 상황의 진영 교체 반복이다. 위치 비교도 어림진의 해당 칸에 한정된다.", "",
        "## 병종별 일반 전투 기여", "",
        "한 부대당 평균 손실량이다. 같은 병종 안에서도 장수·특기·자리·생존 시간이 다르고, 원거리 계열에는 제어·치료 역할이 섞인다. 직접 피해만으로 병종 승률이나 적정 배율을 판단하지 않는다.", "",
        "| 등급 | 고유기 | 병종 | 출전 | 평타 | 잔기술 | 일반 기술 | 고유기 피해 | 지속 피해 | 평균 돌격 |",
        "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for (tier, ults, tag), rows in sorted(roles.items()):
        lines.append(
            f"| {tier} | {'켬' if ults else '끔'} | {tag} | {len(rows)} | {mean(rows, 'basic'):,.0f} | "
            f"{mean(rows, 'minor'):,.0f} | {mean(rows, 'skill'):,.0f} | {mean(rows, 'ultimate'):,.0f} | "
            f"{mean(rows, 'dot'):,.0f} | {mean(rows, 'charges'):.2f} |"
        )
    lines += [
        "", "기병은 평타·일반 기술·돌격, 원거리 계열은 평타 외에 기술·지속 피해·제어로 기여한다. 고유기를 끈 경우에도 양쪽의 일반 공격 기여가 남는다. 병종별 표본 수 차이와 역할 혼합을 남겨 두었으며 기병/원거리의 일괄 상향·하향 근거로 사용하지 않는다.", "",
        "## 함께 처리한 표시 결함", "",
        "- 일반 상태·공격/방어 약화의 실제 시전자를 사건에 기록했다. 최초 화상과 확산을 구분한다.",
        "- 화상 피해 제공자, 번짐 확률 제공자, 확산이 출발하는 피격 부대를 구분한다. 약한 화상으로 더 높은 번짐을 제공한 장수도 표시하며 칠백리는 해당 특기 제공자를 표시한다.",
        "- 기존 엔진이 계산한 갑옷/결계 약화 지원을 공격 사건에 붙여 실제 활용 때만 표시한다. 단순히 상태가 있다는 이유로 지원을 추정하지 않는다.",
        "- 삽화 모드에서 숨겨지던 상태명과 출처 문구를 복원했다. 출처 장수 이름을 작은 알림에 함께 쓰며 동시에 3개, 부대 상태는 최대 2개다.",
        "- 다른 시전자의 같은 효과가 반복 제한에 가려지지 않게 출처별로 구분했다. 일반 잔기술 문구는 계속 숨긴다.", "",
        "재현:", "",
        "```powershell",
        "& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/motion5_role_audit.tscn -- --trials=12",
        "python tools/scripts/motion5_role_summary.py",
        "```", "",
        "원본: [전투별·부대별 측정값](benchmarks/motion5_role_audit.json). 이 결과는 Android 프레임 실측이 아니다.",
    ]
    DEST.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    DOCUMENT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"PASS audit summary: {len(data['role_runs'])} role battles / {len(data['zhou_yu_runs'])} commander runs")


if __name__ == "__main__":
    main()
