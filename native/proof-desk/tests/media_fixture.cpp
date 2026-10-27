// Bounded synthetic motion for exercising the real Windows media decoder.
// This is review-tool test media, never evidence of factory simulation.
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QMediaCaptureSession>
#include <QMediaFormat>
#include <QMediaRecorder>
#include <QPainter>
#include <QTimer>
#include <QUrl>
#include <QVideoFrame>
#include <QVideoFrameInput>
#include <iostream>
int main(int argc, char **argv) {
  QGuiApplication app(argc, argv);
  if (argc != 2 || !QFileInfo(QString::fromUtf8(argv[1])).isAbsolute() ||
      QFileInfo::exists(QString::fromUtf8(argv[1])))
    return 2;
  QMediaCaptureSession session;
  QMediaRecorder recorder;
  QVideoFrameInput input;
  session.setRecorder(&recorder);
  session.setVideoFrameInput(&input);
  QMediaFormat format(QMediaFormat::MPEG4);
  format.setVideoCodec(QMediaFormat::VideoCodec::H264);
  recorder.setMediaFormat(format);
  recorder.setVideoResolution(960, 540);
  recorder.setVideoFrameRate(30);
  recorder.setQuality(QMediaRecorder::HighQuality);
  recorder.setAutoStop(true);
  recorder.setOutputLocation(QUrl::fromLocalFile(QString::fromUtf8(argv[1])));
  int frameNumber = 0;
  bool started = false;
  QObject::connect(&input, &QVideoFrameInput::readyToSendVideoFrame, &app, [&] {
    if (frameNumber == 180) {
      input.sendVideoFrame(QVideoFrame());
      return;
    }
    QImage image(960, 540, QImage::Format_ARGB32);
    image.fill(QColor("#1d2c35"));
    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(QColor("#344750"));
    for (int x = 0; x < 960; x += 60)
      p.drawLine(x, 0, x, 540);
    for (int y = 0; y < 540; y += 60)
      p.drawLine(0, y, 960, y);
    p.setPen(QColor("#dde4ef"));
    p.setFont(QFont("Segoe UI", 18));
    p.drawText(35, 50, "SYNTHETIC MOTION · REVIEW TOOL TEST");
    p.drawText(35, 500,
               QString("Frame %1 / 180 · %2 ms")
                   .arg(frameNumber)
                   .arg(frameNumber * 1000 / 30));
    for (int g = 0; g < 2; ++g) {
      p.save();
      p.translate(365 + g * 185, 280);
      p.rotate((g ? -1 : 1) * frameNumber * 4);
      p.setPen(QPen(QColor("#152632"), 5));
      p.setBrush(g ? QColor("#8fa9b8") : QColor("#c6a574"));
      p.drawEllipse(QPointF(), 95, 95);
      p.setPen(QPen(QColor("#263d48"), 10));
      for (int i = 0; i < 6; ++i) {
        p.rotate(60);
        p.drawLine(0, 0, 80, 0);
      }
      p.setBrush(QColor("#bdcbd0"));
      p.drawEllipse(QPointF(), 16, 16);
      p.restore();
    }
    p.end();
    QVideoFrame frame(image);
    frame.setStartTime(frameNumber * 1000000LL / 30);
    frame.setEndTime((frameNumber + 1) * 1000000LL / 30);
    if (input.sendVideoFrame(frame))
      ++frameNumber;
  });
  QObject::connect(
      &recorder, &QMediaRecorder::recorderStateChanged, &app, [&](auto state) {
        if (state == QMediaRecorder::RecordingState)
          started = true;
        if (started && state == QMediaRecorder::StoppedState) {
          std::cout << "PROOF_MEDIA_FIXTURE " << frameNumber << '\n';
          app.exit(frameNumber == 180 ? 0 : 1);
        }
      });
  QObject::connect(&recorder, &QMediaRecorder::errorOccurred, &app,
                   [&](auto, const QString &error) {
                     std::cerr << error.toStdString() << '\n';
                     app.exit(1);
                   });
  QTimer::singleShot(30000, &app, [&] { app.exit(3); });
  recorder.record();
  return app.exec();
}
