# 클로드 인수인계 — motion.5 전투 후속 작업

작성: 2026-11-17. 사용자가 **“여기까지 하고, 해야 할 목록과 작업하던 내용을 문서로 올려 달라. 클로드에게 시키겠다”**고 요청해 구현을 중단한 시점의 기록이다. 이 문서는 추가 구현 지시를 대신 수행한 결과가 아니라, 현재 코드와 미완료 범위를 전달하기 위한 문서다.

## 1. 바로 이어받을 위치

- 저장소: `firnein/solgukji`, 로컬 `D:\Sol`.
- 작업 브랜치: **`fix/battle-motion5`**. 이 문서를 추가한 스냅샷 커밋에서 계속하면 된다.
- 직전 푸시 완료 기준: `df3d606` — 배치 렌더링·범위 표시·누수 수정.
- 그 이전: `c8e1ca2` — motion.5 복원 병합과 첫 PC 진단, `2068be4` — 원거리 최근접/원형 범위 수정.
- 복원 원본: `origin/motion-5`의 `d6b983d`. APK **1.0z-motion.5 / versionCode 31**에서 복원한 5개 스크립트다.
- 시작 기준 main: `b3bfb39`. **이 작업으로 main을 병합하거나 운영 서버를 배포하지 않았다.**
- 이 스냅샷에는 `df3d606` 이후 작업하던 코드·검사·통계·문서도 함께 보관했다. 완성 배포판으로 취급하지 말고 아래 남은 검토부터 한다.

읽을 문서:

1. [현재 전투 개선 현황](전투_개선_현황.md)
2. [원거리·기병/전설 주유 역할 측정](전투_역할_점검_motion5.md)
3. [기존 삽화 구현과 원화 자산의 한계](전쟁삽화_구현_1116.md)
4. [기존 덱 연계 표시](전투_덱연계_표시_1116.md)

## 2. 사용자의 의도와 유지해야 할 방향

- 기존 덱이 인연·고티어에만 묶이는 문제를 지적했다. **인연이 아닌 장수도 화공·제어·약화 등으로 왜 필요한지 초심자가 알아볼 수 있어야 한다.**
- 불의 확산·방어 약화·다른 장수의 활용이 전투에서 안 보인다는 문제다. 연출을 보탰다고 이 목적이 자동으로 달성되는 것은 아니다.
- 팝콘처럼 병사가 과하게 날아가는 진삼국무쌍식 연출은 줄이라는 피드백을 받았다.
- 사용자가 승인한 삽화 방향과 **고정 사선 시점**을 유지한다. 예전 탑뷰로 되돌리지 않는다.
- 전장을 화면 가운데에만 몰지 말고 상하를 넓게 사용한다. 현재 초기 편성 기준 카메라·세로 프레이밍을 유지한다.
- 복원만 하고 결함을 목록에 남기는 대응에 불만을 표시했다. 측정 가능한 항목은 측정하고, 실제 결함은 수정해야 한다.
- **Android 프레임 측정용 기기 연결 불가**는 이미 확인했다. PC Mobile 렌더러를 Android 실측이라고 표현하거나 연결 요청을 반복하지 않는다.
- 과거 `전투_목표_작업명세.md`의 화면 1/3 폭발·강한 날리기 지시는 이후 피드백보다 우선하지 않는다.
- 피해·확률·게이지 등의 숫자를 근거 없이 조정하지 않는다. 이번 후속 변경은 표시·기록·진단·대표 대열 배치이며 수치 상향은 하지 않았다.

## 3. df3d606까지 완료·푸시한 내용

- 원거리 평타/공격 준비/이동이 사거리 안 최근접 생존·비은신 적을 선택하도록 통일.
- 원형 고유기의 +40 기록 보정과 0.6배 화면 축소 제거, 실제 월드 경계 투영.
- 고유기 예고 `warn_shapes`, 미리보기 기록 불변, 상대 시점 반전.
- `front3/denseLine`·전체·대상 수 제한은 선택된 부대 발자국으로 안내. 띠도 월드 판정 폭으로 투영.
- 불바다 경계를 첫 틱부터 전체 판정 반경으로 표시.
- 병사/그림자 MultiMesh 배치와 연속 GPU 보행. 앞줄 표식 묶음.
- 화살의 실제 시간차 출발·도착과 분산.
- Squad/Soldier 상대 참조, UltFx 예약 효과, 온라인 조합 콜백의 순환 참조 정리.
- 저녁 준비 규칙과 준비 완료 뒤의 명령 경쟁 때문에 실패하던 온라인 검사 수정.

기존 PC 비교: 평균 15.61→7.31ms, 그리기 1,455→525회. 수치는 Windows RTX 4080의 해당 실행 결과다.

## 4. 중단 직전 작업하던 내용 — 이번 스냅샷에 포함

### A. 일반 상태/약화의 출처와 실제 지원 표시

파일: `scripts/battle.gd`, `scripts/battle_view.gd`.

- `inflict/_cut/_shred` 사건에 실제 시전자 `from` 추가.
- 최초 화상은 `spread:false`, 확산은 `spread:true`로 구분.
- 기존 엔진의 갑옷/결계 약화 기여 계산값을 공격 사건의 `assists`로 전달했다. 수치를 새로 더하거나 전투 피해를 바꾸지 않는다.
- 삽화 모드에서 `float_text`가 조기 반환해 기여 문구까지 사라지고, 메달 분기에서 상태 딱지까지 빠지던 경로를 수정했다.
- 출처 장수 이름+역할을 작은 알림으로 표시한다. 알림/연결은 최대 3개, 상태 딱지는 부대당 최대 2개다.
- 같은 효과라도 다른 장수의 기여가 4초 제한에 가려지지 않도록 시전자별로 제한한다.
- 일반 잔기술 문구는 계속 숨긴다. 피해 숫자 전체를 다시 켠 것은 아니다.
- 공격 약화·방어 약화·갑옷/결계 약화도 표시 목록에 포함했다.

### B. 마지막에 수정한 핵심: 확산 경로와 기여 장수는 다르다

파일: `scripts/battle.gd`의 `inflict/_spread_burn_to/_blaze`, `Hud.deck_event`.

- 예전 확산 사건의 `from`은 **불이 번져 나오는 피격 적 부대**다. 이를 화공에 기여한 아군으로 표시하면 잘못된 정보가 된다.
- 내부 상태의 `by`는 기존 지속 피해 출처로 유지한다.
- `spread_by`는 번짐 확률을 제공한 장수를 따로 보존한다. 더 약한 화상을 걸었더라도 번짐 확률이 더 높으면 이 제공자가 기록된다.
- 확산 사건은 `from`에 실제 경로의 출발 부대, `contributor`에 효과 제공자를 둔다. 연결선은 경로를, 이름 알림은 제공자를 따른다.
- 칠백리 `_blaze`는 해당 특기를 제공한 살아 있는 반대 진영 장수 중 가장 큰 값을 가진 자를 표시한다. 동률이면 엔진 부대 순서의 첫 장수다. 피해/번짐 확률 제공자를 칠백리 제공자와 혼동하지 않는다.
- `_spread_burn_to(..., triggered_by := "")`의 선택 인자는 **출처 메타데이터용**이다. 피해·반감 번짐·지속 시간은 그대로다.
- 옛 상태에는 `spread_by`가 없을 수 있어 `by` fallback을 사용한다. 출처가 없는 경우 새 장수를 추정하지 않는다.

**이 B 항목이 가장 마지막 코드 변경이다.** 실제 사건 회귀 검사는 통과했지만, 아래 PC 계측과 교전 이미지가 모두 이 마지막 변경 이후 다시 생성된 것은 아니다. 최종 화면·성능 확인을 다음 작업으로 남긴다.

### C. 대표 병사 접촉선 분리

파일: `scripts/field/war_painting.gd`, `painted_formation.gd`.

- 실제 부대 발자국의 네 분리축으로 서로 가까운 적과의 접촉선을 구한다.
- `contact_limits`, `constrain_foot`로 대표 병사의 발과 공격 내밀기를 각자 접촉선 쪽에 제한한다.
- 실제 전투 엔진의 부대 중심·판정·병력을 움직이는 기능이 아니다.
- 8명 이하 소부대에서 보행·접촉·정지·후열 보충 검사.
- 시드 5100의 8초 표본에서 가까운 반대 진영 발 6쌍→0쌍, 20초 표본도 0쌍.
- 기준은 발 위치 거리 < 작은 병사 높이의 20%. 몸통 실루엣 전체 겹침이 0이라는 주장이 아니다.
- **여러 방향의 적에게 동시에 둘러싸인 경우는 별도 확인 필요.** 현재 제약을 순서대로 한 번 적용하므로 뒤쪽 제약이 앞쪽 제약에 영향을 줄 가능성을 검토한다. 재현 없이 새 충돌 판정을 추가하지 않는다.

### D. 빠뜨렸던 역할 비교

파일: `tests/motion5_role_audit.gd/.tscn`, `tools/scripts/motion5_role_summary.py`.

- 전설·불멸·신화, 동일 편성 고유기 켬/끔·진영 교체: **144전투**.
- 전설 일반 책사 주유/종회/육손/강유, 같은 팀원·상대·앞/뒤 자리·진영 교체: **192전투**.
- 평타·잔기술·일반 기술·고유기·반격·기타 직접 피해를 분리. 초과 피해와 분담 피해의 취급은 역할 문서에 명시했다.
- 전설 주유는 고유기 0회인데도 평타·잔기술·화상으로 기여한다. 예: 앞 자리 평균 평타 약 3,560, 지속 피해 약 5,412. 고유기가 없다는 이유로 무기여라고 볼 근거는 없었다.
- 특정 12개 상황의 양 진영 반복이며 전체 밸런스 검증은 아니다. 치료/제어/지원까지 직접 피해와 합산해 승률 균형을 판정하지 않았다.
- 계측기 전/후 사건 JSON·승패·잔존 부대 동일 검사 통과.
- 출처 메타데이터 추가 전/후 보관한 336전투의 집계 행도 동일함을 확인했다.
- 원본/요약은 Git에 보관해 재측정 없이도 내용을 볼 수 있다.

## 5. 검증한 범위와 중단 시 상태

Godot **4.4.1**, Windows. 실행 파일 `tools/Godot_v4.4.1-stable_win64_console.exe`.

| 항목 | 마지막 확인 |
|---|---|
| `deck_visual` | 실제 엔진 사건으로 최초 화상/약화/지원/지원 만료/다른 시전자/최대 3개/상대 시점 검사 통과. 화상 피해 제공자≠번짐 제공자, 칠백리 제공자 분리 검사도 통과 |
| `motion5_combat_regression` | 돌격 주행 거리·1회 소비·창벽 정면/측면·수몰·원거리·반격·고유기 조건 통과 |
| `target_area_regression` | 최근접·도형·예고·불바다·상대 시점 통과 |
| `determinism` | 마지막 출처 수정 뒤 30판 실패 0 |
| `rear_morale_regression` / `inyeon` | 마지막 출처 수정 뒤 통과 / 실패 0 |
| `net --players=2` | 마지막 출처 수정 뒤 24.4초, 완주·재접속, 사람끼리 대전 6건 양쪽 집계, 거부 검사 16/16, 오류 0 |
| PC Vulkan Mobile 혼합 전체 재생 | 마지막 출처 수정 뒤 통과. 화풍 전환·장면 재사용 포함 |
| 누수/스크립트 오류 | 위 최종 로그를 검색했을 때 없음 |
| 후속 PC 성능 | 평균 8.33ms / p95 11.56ms / 최대 18.23ms / 33.3ms 초과 0% / 평균 576호출. **마지막 확산 제공자 분리 전 측정** |
| Android 실측 | 기기 연결 불가, 수행하지 않음 |
| 새 APK | **미빌드·미업로드**. 현재 고정 APK에 이번 소스 변경이 들어갔다고 보면 안 됨 |
| 실행 중 작업 | 중단 요청 후 확인 시 Godot 실행 프로세스 없음. 새 검사를 시작하지 않음 |

로컬 로그는 `build/`에 있으며 기본 Git 제외다. 주요 파일:

- `remaining_check_*.log`, `remaining_net_final.log`, `remaining_mobile_full.log`
- `motion5_deck_provenance.log`, `motion5_role_audit_final.log`
- `motion5_remaining_profile.log`, `motion5_remaining_visual.log`, `motion5_contact20.log`

Git에 남긴 원본:

- `docs/benchmarks/motion5_role_audit.json`
- `docs/benchmarks/motion5_contact_samples.json`
- `docs/benchmarks/motion5_pc_remaining_final.json`
- `docs/benchmarks/motion5_remaining_combat.png`

이미지/겹침 표본은 마지막 출처 필드 수정 전 캡처일 수 있다. 최종 화면 증거와 구분한다.

## 6. 해야 할 목록 — 권장 순서

### 우선: 현재 스냅샷 마무리

- [ ] B의 확산 출처 변경을 리뷰한다. `from/contributor/by/spread_by`의 의미, 약한 화상+강한 번짐, 칠백리, 옛 기록 fallback을 확인한다.
- [ ] 최종 코드로 실제 화공·갑옷/결계 약화·공격 약화 전투를 캡처한다. **출처 장수 이름이 읽히는지**, 피격 적이 기여 장수로 보이지 않는지 확인한다.
- [ ] 400×800에서 상태 딱지/이름/기여 알림/고유기 컷인의 겹침과 어두운 글씨 대비를 검토한다. 알림 상한 3개를 유지한다.
- [ ] 접촉선의 다대일·모서리·양방향 압박·작은 부대 손실/보충 사례를 추가 확인한다. 수치나 실제 충돌 판정을 건드리지 않고 대표 대열만 다듬는다.
- [ ] 마지막 출처 수정 이후의 PC 프로파일을 같은 조건으로 한 번 더 저장한다. 기존 8.33ms 수치를 마지막 코드 성능으로 단정하지 않는다.
- [ ] 변경이 추가되면 관련 회귀 검사만 다시 실행하고, 문서의 완료/미완료를 갱신한다.

### 남아 있는 제작·사용성

- [ ] **병종별 방향 그림과 팔다리/공격 동작 원화 프레임**. 현재는 4×4 아틀라스의 병종/진영별 정지 그림과 GPU 메시 변형이다. 실제 방향별 애니메이션을 만들었다고 표시하지 않는다.
- [ ] **나무·강가의 삽화 자산/지면 표현**. 승인된 원화와의 스타일 차이를 줄인다.
- [ ] 초심자가 편성 때도 인연 밖의 장수 역할을 알 수 있게 하는 설명·추천. 현재 전투 출처 알림과 상태명 수정만으로 편성 추천까지 완료된 것은 아니다.
- [ ] 화공 외 제어·약화·반격·회복 등 덱의 실제 기여를 같은 원칙으로 확인한다. 현재 정확한 활용 메타데이터는 화상/수몰 플래그와 갑옷/결계 지원에 한정된다. 모든 버프의 인과 기여 점수를 구현한 것은 아니다.
- [ ] 역할 표본을 넓히려면 병종별 카드/PV/자리/생존·치료·제어를 함께 보며 측정한다. 현재 표만으로 일괄 피해 상향/하향하지 않는다.

### 배포·기기

- [ ] 다음 요청 범위에 맞춰 새 APK를 빌드한다. 현재 export preset은 **1.0z / code 27**, 복원 APK는 **motion.5 / code 31**이므로 버전 코드 역행에 주의한다. 실제 최신 배포를 확인한 후 증가시킨다.
- [ ] 새 APK의 파싱/내보내기·패키지/버전·리소스 포함을 확인하고, 프로젝트 규칙의 고정 `build/solgukji.apk`(Git LFS) 갱신 여부를 명확히 기록한다.
- [ ] 서버 권위 판정 변경은 서버도 같은 소스여야 반영된다. APK만 새로 만들어 운영 서버 판정까지 바뀌었다고 하지 않는다. main 병합·운영 배포는 수행하지 않은 상태다.
- [ ] Android 기기를 실제 사용할 수 있게 된 경우에만 프레임 시간/발열/메모리를 측정한다. 현재는 연결 불가다.

## 7. 재현 명령

프로젝트 루트에서 PowerShell. 개발 도구는 로컬에 있으며 원격 저장소에 Godot 실행 파일은 없다.

```powershell
& tools/Godot_v4.4.1-stable_win64_console.exe --path solgukji_godot --resolution 400x800 res://tests/deck_visual.tscn -- --shot
& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/motion5_combat_regression.tscn
& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/target_area_regression.tscn
& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/determinism.tscn
& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/rear_morale_regression.tscn
& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/inyeon.tscn
& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/net.tscn -- --players=2
& tools/Godot_v4.4.1-stable_win64_console.exe --path solgukji_godot --rendering-method mobile --resolution 400x800 res://tests/formation_preview.tscn -- --painting --mixed --full
```

```powershell
# 최종 출처/접촉선 화면 확인
& tools/Godot_v4.4.1-stable_win64_console.exe --path solgukji_godot --resolution 400x800 res://tests/motion5_replay.tscn -- --validate-only --capture-at=8 --contact-audit --shot --tag=handoff_check
# 다른 성능 측정/전투 검사와 동시에 실행하지 않는다
& tools/Godot_v4.4.1-stable_win64_console.exe --path solgukji_godot --resolution 400x800 res://tests/motion5_replay.tscn -- --secs=15 --skip=3 --tag=handoff_final
# 역할 통계 전체 재생성: 336전투이므로 단순 화면 변경 때마다 반복할 필요 없음
& tools/Godot_v4.4.1-stable_win64_console.exe --headless --path solgukji_godot res://tests/motion5_role_audit.tscn -- --trials=12
python tools/scripts/motion5_role_summary.py
```

`--legacy-painting`은 이전 병사별 그리기와 비교하기 위한 진단 옵션이다. 게임 기본 품질 설정이 아니다.

## 8. 작업 트리 주의

- `assets/faces/*.png.import`가 다수 수정으로 보이지만 줄바꿈/인덱스 상태 때문에 생긴 표시가 있었다. 실제 논리 diff가 없는 파일은 커밋하지 않았다. 일괄 reset/정리하지 않는다.
- `.claude/`와 `assets_src/kaykit/Mage_mage_texture.png.import~RF6d696ac4.TMP`는 작업 전부터 있던 항목이다. 이번 작업과 무관하며 삭제/커밋하지 않는다.
- 사용자 중단 요청 이후 새 구현이나 새 테스트를 시작하지 않았다. 현재 스냅샷과 문서 저장·푸시만 마무리했다.
