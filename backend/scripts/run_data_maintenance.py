# 파일명: run_data_maintenance.py
# 역할: 배포 환경의 정기 작업에서 데이터 보존 정책을 한 번 실행한다.

from core.database import SessionLocal
from services.data_maintenance import DataMaintenanceService


def main() -> None:
    db = SessionLocal()
    try:
        deleted = DataMaintenanceService().runOnce(db)
        print(deleted)
    finally:
        db.close()


if __name__ == "__main__":
    main()
