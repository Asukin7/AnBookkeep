# ONNX Runtime's JNI layer resolves Java classes and members by their original
# names. onnxruntime-android 1.21.1 does not bundle consumer keep rules, so R8
# would otherwise rename or remove types such as TensorInfo and abort the
# process from native code during OCR inference.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** {
    native <methods>;
}
