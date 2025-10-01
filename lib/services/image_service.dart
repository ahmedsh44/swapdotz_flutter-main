import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

class ImageService {
  static final ImagePicker _picker = ImagePicker();
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // Maximum dimensions for listing images
  static const int maxWidth = 1024;
  static const int maxHeight = 1024;
  static const int compressionQuality = 85;
  
  /// Pick and process an image from gallery or camera
  static Future<File?> pickAndProcessImage({
    required BuildContext context,
    ImageSource source = ImageSource.gallery,
    bool allowCropping = true,
  }) async {
    try {
      // Pick image - COMPLETELY CLEAN: No aspectRatioPresets
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      
      if (pickedFile == null) return null;
      
      File imageFile = File(pickedFile.path);
      
      // Crop image if allowed
      if (allowCropping) {
        final croppedFile = await _cropImage(imageFile, context);
        if (croppedFile != null) {
          imageFile = croppedFile;
        } else {
          return null;
        }
      }
      
      // Compress image
      final compressedFile = await _compressImage(imageFile);
      
      return compressedFile;
    } catch (e) {
      print('Error picking and processing image: $e');
      return null;
    }
  }

  /// Pick multiple images from gallery
  static Future<List<File>?> pickMultipleImages({
    required BuildContext context,
  }) async {
    try {
      // COMPLETELY CLEAN: No aspectRatioPresets
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      
      if (pickedFiles.isEmpty) return null;
      
      return pickedFiles.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      print('Error picking multiple images: $e');
      return null;
    }
  }

  /// Pick image from camera
  static Future<File?> pickImageFromCamera({
    required BuildContext context,
    bool allowCropping = true,
  }) async {
    try {
      // COMPLETELY CLEAN: No aspectRatioPresets
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      
      if (pickedFile == null) return null;
      
      File imageFile = File(pickedFile.path);
      
      if (allowCropping) {
        final croppedFile = await _cropImage(imageFile, context);
        if (croppedFile != null) {
          imageFile = croppedFile;
        } else {
          return null;
        }
      }
      
      return await _compressImage(imageFile);
    } catch (e) {
      print('Error picking image from camera: $e');
      return null;
    }
  }
  
  /// Crop an image
  static Future<File?> _cropImage(File imageFile, BuildContext context) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.black87,
            toolbarWidgetColor: Colors.white,
            statusBarColor: Colors.black87,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: Colors.blue,
            dimmedLayerColor: Colors.black.withOpacity(0.7),
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white.withOpacity(0.5),
            cropFrameStrokeWidth: 2,
            cropGridStrokeWidth: 1,
            cropGridRowCount: 2,
            cropGridColumnCount: 2,
            hideBottomControls: false,
            showCropGrid: true,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.square,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.original,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            aspectRatioPickerButtonHidden: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            minimumAspectRatio: 0.5,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.original,
            ],
          ),
        ],
      );
      
      return croppedFile != null ? File(croppedFile.path) : null;
    } catch (e) {
      print('Error cropping image: $e');
      return null;
    }
  }
  
  /// Compress an image file
  static Future<File> _compressImage(File imageFile) async {
    try {
      final filePath = imageFile.path;
      final fileName = path.basename(filePath);
      final fileExtension = path.extension(fileName);
      
      final dir = path.dirname(filePath);
      final targetPath = path.join(
        dir,
        '${path.basenameWithoutExtension(fileName)}_compressed$fileExtension',
      );
      
      final result = await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        targetPath,
        quality: compressionQuality,
        minWidth: maxWidth,
        minHeight: maxHeight,
        keepExif: false,
      );
      
      return result != null ? File(result.path) : imageFile;
    } catch (e) {
      print('Error compressing image: $e');
      return imageFile;
    }
  }
  
  /// Upload image to Firebase Storage
  static Future<String?> uploadImage({
    required File imageFile,
    required String path,
    void Function(double)? onProgress,
  }) async {
    try {
      final ref = _storage.ref().child(path);
      final uploadTask = ref.putFile(imageFile);
      
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress);
        });
      }
      
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }
  
  /// Upload multiple images
  static Future<List<String>> uploadMultipleImages({
    required List<File> imageFiles,
    required String basePath,
    void Function(int current, int total)? onProgress,
  }) async {
    final List<String> uploadedUrls = [];
    
    for (int i = 0; i < imageFiles.length; i++) {
      if (onProgress != null) {
        onProgress(i, imageFiles.length);
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imagePath = '$basePath/image_${timestamp}_$i.jpg';
      
      final url = await uploadImage(
        imageFile: imageFiles[i],
        path: imagePath,
      );
      
      if (url != null) {
        uploadedUrls.add(url);
      }
    }
    
    return uploadedUrls;
  }
  
  /// Delete image from Firebase Storage
  static Future<bool> deleteImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
      return true;
    } catch (e) {
      print('Error deleting image: $e');
      return false;
    }
  }
  
  /// Delete multiple images
  static Future<void> deleteMultipleImages(List<String> imageUrls) async {
    for (final url in imageUrls) {
      await deleteImage(url);
    }
  }
}