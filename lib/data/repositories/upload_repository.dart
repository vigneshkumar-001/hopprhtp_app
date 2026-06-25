import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Uploads images to the backend (`POST /uploads`, multipart) and returns the
/// stored file's absolute URL — used for dispatch photos and waybill images.
class UploadRepository {
  UploadRepository(this._dio);

  final Dio _dio;

  /// Uploads the image at [filePath] and returns its absolute URL.
  Future<String> uploadImage(String filePath) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    return apiCall(
      () => _dio.post('/uploads', data: form),
      (d) => asString(asMap(d)['url']),
    );
  }
}
