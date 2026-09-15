# 파일명: run_data_maintenance.py
# 역할: 배포 환경의 정기 작업에서 데이터 보존 정책을 한 번 실행한다.

from core.database import SessionLocal
from services.data_maintenance import DataMaintenanceService


# 함수이름: main
# 함수역할:
# - 별도 DB 세션에서 데이터 보관 정리를 한 번 실행하고 삭제 집계를 출력한 뒤 세션을 닫는다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def main() -> None:
    db = SessionLocal()
    try:
        deleted = DataMaintenanceService().runOnce(db)
        print(deleted)
    finally:
        db.close()


if __name__ == "__main__":
    main()
