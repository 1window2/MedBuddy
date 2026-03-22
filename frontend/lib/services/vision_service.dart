import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class VisionService {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);

  // 사진을 찍고 텍스트를 추출하여 반환하는 함수
  Future<String?> captureAndRecognizeText() async {
    // 1. 카메라로 사진 찍기 (갤러리로 변경하려면 ImageSource.gallery 사용)
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return null; // 사용자가 취소한 경우

    // 2. ML Kit가 읽을 수 있는 포맷으로 변환
    final inputImage = InputImage.fromFilePath(image.path);

    // 3. 텍스트 추출
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    
    // 이 단계에서 정규식을 사용해 'TextAnalyzer' 역할을 포함시킬 수 있어.
    // 지금은 추출된 전체 텍스트를 그대로 반환할게.
    return recognizedText.text; 
  }

  void dispose() {
    _textRecognizer.close();
  }
}