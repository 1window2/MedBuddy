// 파일명: data_use_info_ui_boundary.dart
// 역할: 현재 앱의 데이터 이용을 설명한다. 확정되지 않은 배포용 약관이나 보관 기간을 만들지 않는다.
import 'package:flutter/material.dart';

import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_page_header.dart';

class DataUseInfoUI extends StatelessWidget {
  final bool isEnglish;

  const DataUseInfoUI({super.key, required this.isEnglish});

  String _text(String ko, String en) => isEnglish ? en : ko;

  Widget _section(String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(fontSize: 16, height: 1.5)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MedBuddyColors.pageBackground,
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          MedBuddyPageHeader(
            title: _text('데이터 이용 안내', 'Data use guide'),
            subtitle: _text(
              '개인정보의 이용과 보관 방법을 확인합니다.',
              'Review how your information is used and stored.',
            ),
            onBackRequested: () => Navigator.of(context).pop(),
            backTooltip: _text('뒤로', 'Back'),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    _section(
                      _text('계정과 복약 정보', 'Account and medication data'),
                      _text(
                        '로그인에는 Firebase 인증을 사용합니다. 약 이름·용량·일정·복용 기록과 설정은 '
                            'MedBuddy 서버에서 계정에 연결해 관리합니다. 서버의 사용자 식별값을 해시로 '
                            '구분하더라도 계정과 연결된 건강 정보가 완전히 익명화되는 것은 아닙니다.',
                        'Sign-in uses Firebase Authentication. Medication names, doses, schedules, dose records '
                            'and preferences are associated with your account on the MedBuddy server. '
                            'A hashed user identifier does not make account-linked health information fully anonymous.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text(
                        '처방전 사진과 글자 인식',
                        'Prescription photos and text recognition',
                      ),
                      _text(
                        '처방전 사진의 글자 인식과 개인정보 제거는 기기에서 먼저 수행합니다. '
                            '현재 처방전 분석 경로는 원본 사진 대신 필터를 거친 텍스트를 서버로 보냅니다. '
                            '서버는 약 정보 조회와 필요한 경우 Gemini를 이용한 텍스트 분석을 수행합니다. '
                            '자동 제거가 모든 개인정보를 찾아낸다고 보장할 수 없으므로 불필요한 개인정보는 '
                            '촬영 전에 가려주세요.',
                        'Prescription OCR and personal-data filtering run on your device first. The current '
                            'prescription analysis sends filtered text, not the original photo, to the server. '
                            'The server looks up medication information and may use Gemini for text analysis. '
                            'Automatic filtering cannot guarantee removal of every identifier; cover unnecessary '
                            'personal information before taking the photo.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text(
                        '알약 식별·건강 추천과 외부 AI',
                        'Pill identification, health tips and external AI',
                      ),
                      _text(
                        '낱알약 식별을 요청하면 선택한 알약 사진이 서버와 외부 AI인 Google Gemini로 '
                            '전송되어 분석될 수 있습니다. 건강 관리 추천을 요청하면 복용 중인 약 정보도 '
                            '서버를 통해 Gemini에 전달되어 추천 생성에 사용됩니다. '
                            '얼굴이나 신분증 등 불필요한 개인정보가 사진에 포함되지 않게 해주세요. '
                            'AI 분석과 추천은 틀릴 수 있으며 진단이나 처방을 대신하지 않습니다. '
                            'AI 식별이 필요하지 않으면 직접 등록을 이용할 수 있습니다.',
                        'Pill identification can send your selected pill photos through the server to Google Gemini '
                            'for analysis. Health recommendation requests also send medication information '
                            'through the server to Gemini to generate recommendations. '
                            'Keep faces, identity documents and other unnecessary personal data out of photos. '
                            'AI results can be wrong and do not replace diagnosis or prescriptions. '
                            'Manual entry is available when you do not need AI identification.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text('외부 AI 이용 시 주의', 'Before using external AI'),
                      _text(
                        '무료 Gemini API를 사용하는 환경에서는 입력 내용과 응답이 서비스 개선에 '
                            '사용되거나 검토될 수 있으며, 개인정보·민감정보를 전송해서는 안 됩니다. '
                            '이 환경에서는 실제 환자의 처방전·복약 정보로 AI 분석이나 건강 추천을 '
                            '이용하지 마세요. 이름을 지우거나 계정 식별값을 해시로 바꾸는 것만으로 '
                            '건강 정보가 익명화되지는 않습니다.',
                        'In environments using the unpaid Gemini API, inputs and responses may be used '
                            'for service improvement or reviewed. Personal and sensitive information must '
                            'not be submitted. Do not use AI analysis or health recommendations with real '
                            'patient prescriptions or medication data in those environments. Removing '
                            'names or hashing account identifiers does not by itself anonymize health data.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text('보호자 연동과 채팅', 'Caregiver links and chat'),
                      _text(
                        '연동된 환자와 보호자는 권한 범위 안에서 복약 일정·기록과 채팅 내용을 공유합니다. '
                            '채팅에 약이나 병원·약국 카드를 보내면 상대방도 해당 내용을 볼 수 있습니다. '
                            '복용 완료 표시는 사용자가 기록한 상태이며 실제 복용을 증명하지 않습니다. '
                            '연동 해제는 이미 상대방이 확인하거나 별도로 저장한 정보까지 회수하지는 않습니다.',
                        'Linked patients and caregivers share schedules, dose records and chat within their '
                            'access permissions. Sending a medication or healthcare place card shares those details '
                            'with the recipient. A taken status is a user record, not proof of ingestion. '
                            'Unlinking cannot retrieve information the other person has already seen or saved.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text('위치와 지도', 'Location and maps'),
                      _text(
                        '주변 병원·약국을 찾을 때 현재 위치 또는 이동한 지도의 검색 위치를 사용합니다. '
                            '검색 좌표는 주변 시설 조회를 위해 서버로 전달되고, 지도 표시와 길찾기에는 '
                            '지도 제공 서비스가 사용됩니다. 위치 권한을 거절한 경우 현재 위치를 자동으로 '
                            '사용할 수 없습니다. 공유한 장소 정보와 내 위치는 구분해서 확인해주세요.',
                        'Nearby hospital and pharmacy searches use your current position or the search position '
                            'on the map. Coordinates are sent to the server to find nearby facilities; map providers '
                            'are used for maps and directions. Denying location access prevents automatic use of your '
                            'current position. A shared place is not necessarily your own location.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text(
                        '기기 저장·위젯·알림',
                        'Device storage, widgets and notifications',
                      ),
                      _text(
                        '빠른 표시와 오프라인 복용 기록을 위해 일부 일정·설정·전송 대기 기록을 기기에 '
                            '저장합니다. 직접 등록에 첨부한 약 사진은 앱의 기기 저장소에 보관합니다. '
                            '홈 화면 위젯과 잠금 화면 알림에 약 정보가 보일 수 있으므로 공개 범위를 확인해주세요. '
                            '서버에 보내지 못한 기록은 연결 복구 후 전송되며, 앱 삭제나 기기 데이터 삭제 시 '
                            '아직 전송하지 못한 기록이 사라질 수 있습니다.',
                        'Some schedules, preferences and pending dose records are cached on this device for '
                            'quick access and offline recording. Photos attached to manual entries are stored in '
                            'app storage on this device. Widgets and lock-screen alerts may show medication '
                            'information; review their visibility. Pending records sync when connectivity returns. '
                            'Uninstalling or clearing app data can remove records not yet uploaded.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text('복약 기록 파일 공유', 'Sharing medication record files'),
                      _text(
                        '복약 기록을 CSV 파일로 내보내면 선택한 기간의 약 정보와 기록이 포함됩니다. '
                            '공유 전 내용과 받을 앱·상대방을 확인해주세요. 계정 내부 식별값을 제외해도 '
                            '파일에는 건강 정보가 담기므로 안전하게 보관해야 합니다. '
                            '공유용 임시 파일은 앱의 기기 캐시에 만들어집니다. 계정 삭제 시 정리를 '
                            '시도하고 이후 내보내기 때 오래된 임시 파일을 정리하지만, 상대방이나 '
                            '다른 앱이 저장한 사본은 회수할 수 없습니다.',
                        'Exported CSV files contain medication details and records for the selected period. '
                            'Review the contents and the receiving app or person before sharing. Even without '
                            'internal account identifiers, the file contains health information and needs safe storage. '
                            'Temporary sharing files are created in app cache. The app attempts to clear them on '
                            'account deletion and removes older temporary files on later exports. Copies saved by '
                            'other people or apps cannot be recalled.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text('삭제와 보관 기준', 'Deletion and retention'),
                      _text(
                        '복용 기간이 끝나도 이전 기록을 확인할 수 있도록 약 정보가 남을 수 있습니다. '
                            '계정 삭제는 환경설정 > 계정에서 요청할 수 있으며 로그인 제공자 확인 등 추가 '
                            '절차가 필요할 수 있습니다. 일반 회원의 로그아웃이나 앱 삭제만으로 서버의 '
                            '계정 데이터가 삭제되지는 않습니다. 게스트 로그아웃은 화면에서 삭제 안내를 '
                            '확인한 뒤 게스트 복약 정보·일정·연동·설정 데이터를 삭제하는 절차입니다.',
                        'Medication information may remain after a course ends so you can review earlier records. '
                            'Request account deletion in Settings > Account; additional identity checks may apply. '
                            'Signing out of a registered account or uninstalling does not by itself delete server '
                            'account data. Guest sign-out is different: after the deletion warning is confirmed, '
                            'guest medication, schedule, link and settings data are deleted.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text('계정 삭제 범위', 'What account deletion covers'),
                      _text(
                        '계정 삭제가 처리되면 서버의 해당 계정에 연결된 약·복용 기록·설정·보호자 연동·'
                            '연동 채팅·알림 데이터를 삭제합니다. 삭제한 계정의 재접근을 막거나 삭제를 '
                            '재시도하기 위한 식별값과 처리 상태는 남을 수 있습니다. '
                            '운영 백업·로그와 외부 서비스의 정보는 별도로 관리되므로 모든 사본이 '
                            '같은 순간에 삭제되는 것은 아닙니다. 이미 다른 앱이나 상대방에게 공유한 '
                            '파일·내용은 회수할 수 없습니다.',
                        'Account deletion removes the account-linked medication data, dose records, preferences, '
                            'caregiver links, linked chat and notification data from the service database. '
                            'Identifiers and deletion status may remain to block access or retry deletion. '
                            'Operational backups, logs and external-service data are managed separately, so '
                            'all copies are not removed at the same instant. Files or content already shared '
                            'with other apps or people cannot be recalled.',
                      ),
                    ),
                    const Divider(height: 1),
                    _section(
                      _text(
                        '내 정보 확인과 관리',
                        'Access and manage your information',
                      ),
                      _text(
                        '약 정보는 복약함에서, 날짜별 복용 기록은 일정의 복용 기록에서 확인하고 '
                            '수정할 수 있습니다. 복약 기록은 원하는 기간을 선택해 CSV로 내보낼 수 '
                            '있습니다. 보호자 연동은 내 정보에서, 알림과 계정 삭제는 환경설정에서 '
                            '관리합니다. 문의를 위해 공개 게시판에 처방전·연락처·복약 기록을 올리지 마세요.',
                        'Review and edit medications in My Medications and dated dose records in the '
                            'schedule history. You can export records for a selected period as CSV. '
                            'Manage caregiver links in My Info, and notifications or account deletion '
                            'in Settings. Do not post prescriptions, contact details or medication records '
                            'on a public issue board when seeking help.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
