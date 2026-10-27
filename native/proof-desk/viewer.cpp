#include <QMediaPlayer>
#include <QVideoFrame>
#include <QVideoSink>
#include <QtWidgets>
#include <cmath>
#include <functional>

namespace {
QJsonObject readObject(const QString &path) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly) || file.size() > 4 * 1024 * 1024)
    throw std::runtime_error(("Cannot read " + path).toStdString());
  QJsonParseError error;
  auto doc = QJsonDocument::fromJson(file.readAll(), &error);
  if (error.error != QJsonParseError::NoError || !doc.isObject())
    throw std::runtime_error("Invalid proof record");
  return doc.object();
}
void saveObject(const QString &path, const QJsonObject &value) {
  QSaveFile file(path);
  if (!file.open(QIODevice::WriteOnly) ||
      file.write(QJsonDocument(value).toJson()) < 0 || !file.commit())
    throw std::runtime_error("Cannot save review draft");
}
QString hashFile(const QString &path) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly))
    return {};
  QCryptographicHash hash(QCryptographicHash::Sha256);
  if (!hash.addData(&file))
    return {};
  return QString::fromLatin1(hash.result().toHex());
}
QString wslPath(QString path) {
  path = QDir::fromNativeSeparators(path);
  if (path.size() > 2 && path[1] == ':')
    return "/mnt/" + path.left(1).toLower() + path.mid(2);
  throw std::runtime_error("The review store must be on a local Windows drive");
}
QString timestamp(qint64 ms) {
  return QString("%1:%2.%3")
      .arg(ms / 60000, 2, 10, QChar('0'))
      .arg(ms / 1000 % 60, 2, 10, QChar('0'))
      .arg(ms % 1000, 3, 10, QChar('0'));
}
QLabel *label(const QString &text, const char *name = nullptr) {
  auto *l = new QLabel(text);
  l->setWordWrap(true);
  if (name)
    l->setObjectName(name);
  l->setTextFormat(Qt::PlainText);
  return l;
}
QPushButton *button(const QString &text, const QString &tip = {}) {
  auto *b = new QPushButton(text);
  b->setCursor(Qt::PointingHandCursor);
  b->setToolTip(tip.isEmpty() ? text : tip);
  b->setAccessibleName(text);
  return b;
}
void annotations(QPainter &painter, const QRectF &rect, const QJsonArray &marks,
                 qint64 time, bool clip) {
  int number = 0;
  painter.setRenderHint(QPainter::Antialiasing);
  auto color = QColor("#ffc17b");
  for (auto value : marks) {
    auto a = value.toObject();
    ++number;
    if (clip && std::abs(a["time_ms"].toInteger() - time) > 100)
      continue;
    QPointF p(rect.x() + rect.width() * a["x"].toDouble(),
              rect.y() + rect.height() * a["y"].toDouble());
    QPointF end(rect.x() + rect.width() * a["end_x"].toDouble(),
                rect.y() + rect.height() * a["end_y"].toDouble());
    painter.setPen(QPen(color, 3));
    if (QLineF(p, end).length() > 3) {
      painter.drawLine(p, end);
      auto angle = std::atan2(end.y() - p.y(), end.x() - p.x());
      painter.drawLine(end, end - QPointF(14 * std::cos(angle - .45),
                                          14 * std::sin(angle - .45)));
      painter.drawLine(end, end - QPointF(14 * std::cos(angle + .45),
                                          14 * std::sin(angle + .45)));
    }
    painter.setBrush(color);
    painter.setPen(Qt::NoPen);
    painter.drawEllipse(p, 15, 15);
    painter.setPen(QColor("#182330"));
    auto font = painter.font();
    font.setBold(true);
    font.setPixelSize(15);
    painter.setFont(font);
    painter.drawText(QRectF(p.x() - 15, p.y() - 15, 30, 30), Qt::AlignCenter,
                     QString::number(number));
  }
}
class Canvas final : public QWidget {
public:
  QImage image;
  QJsonArray marks;
  QString mediaId;
  QString kind;
  QString error;
  QMediaPlayer player;
  QVideoSink sink;
  qint64 frameTime = 0;
  double zoom = 1;
  QPointF pan;
  QString tool = "pan";
  bool locked = false;
  std::function<void(const QJsonObject &, const QImage &)> onMark;
  std::function<void(qint64, qint64)> onPosition;
  std::function<void()> onReady;
  explicit Canvas(QWidget *parent = nullptr) : QWidget(parent) {
    setMinimumSize(220, 220);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    setFocusPolicy(Qt::StrongFocus);
    setAccessibleName("Evidence image. Mouse wheel zooms; drag to pan. N adds "
                      "a note at the center.");
    player.setVideoSink(&sink);
    connect(&sink, &QVideoSink::videoFrameChanged, this,
            [this](const QVideoFrame &frame) {
              auto next = frame.toImage();
              if (!next.isNull()) {
                image = next;
                frameTime = qMax<qint64>(0, frame.startTime() / 1000);
                update();
                if (onReady)
                  onReady();
              }
            });
    connect(&player, &QMediaPlayer::positionChanged, this, [this](qint64 p) {
      if (onPosition)
        onPosition(p, player.duration());
    });
    connect(&player, &QMediaPlayer::durationChanged, this, [this](qint64 d) {
      if (onPosition)
        onPosition(player.position(), d);
    });
    connect(&player, &QMediaPlayer::errorOccurred, this,
            [this](QMediaPlayer::Error, const QString &e) {
              error = e;
              update();
            });
  }
  void load(const QString &path, const QJsonObject &media,
            const QJsonArray &all) {
    player.stop();
    player.setSource(QUrl());
    image = {};
    error = {};
    mediaId = media["id"].toString();
    kind = media["kind"].toString();
    marks = {};
    frameTime = 0;
    zoom = 1;
    pan = {};
    for (auto value : all)
      if (value.toObject()["media"].toString() == mediaId)
        marks.append(value);
    if (!QFileInfo::exists(path) ||
        hashFile(path) != media["sha256"].toString()) {
      error = "Evidence is missing or changed. Ask the agent to resubmit.";
      update();
      return;
    }
    if (kind == "clip") {
      player.setSource(QUrl::fromLocalFile(path));
      player.pause();
    } else {
      QImageReader reader(path);
      if (reader.size().width() > 16000 || reader.size().height() > 16000)
        error = "Image exceeds the viewer size limit";
      else
        image = reader.read();
      if (image.isNull())
        error = "Image could not be decoded";
    }
    update();
  }
  QRectF imageRect() const {
    if (image.isNull())
      return {};
    QSizeF size = image.size();
    size.scale(QSizeF(width() - 24, height() - 24), Qt::KeepAspectRatio);
    size *= zoom;
    return QRectF(
        QPointF((width() - size.width()) / 2, (height() - size.height()) / 2) +
            pan,
        size);
  }
  QImage markedFrame() const {
    if (image.isNull())
      return {};
    QImage out = image.convertToFormat(QImage::Format_ARGB32);
    QPainter p(&out);
    annotations(p, QRectF(QPointF(), out.size()), marks, frameTime,
                kind == "clip");
    return out;
  }
  void fit() {
    zoom = 1;
    pan = {};
    update();
  }

protected:
  QPointF down, last;
  bool dragging = false;
  void paintEvent(QPaintEvent *) override {
    QPainter p(this);
    p.fillRect(rect(), QColor("#1d2c35"));
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    if (!error.isEmpty()) {
      p.setPen(QColor("#ffbd7b"));
      p.drawText(rect().adjusted(30, 30, -30, -30),
                 Qt::AlignCenter | Qt::TextWordWrap, error);
      return;
    }
    if (image.isNull()) {
      p.setPen(QColor("#90a6bc"));
      p.drawText(rect(), Qt::AlignCenter,
                 kind == "clip" ? "Loading clip…"
                                : "Select evidence to review");
      return;
    }
    auto r = imageRect();
    p.drawImage(r, image);
    annotations(p, r, marks, frameTime, kind == "clip");
  }
  void wheelEvent(QWheelEvent *e) override {
    zoom = qBound(.25, zoom * (e->angleDelta().y() > 0 ? 1.15 : 1 / 1.15), 12.);
    update();
    e->accept();
  }
  void mousePressEvent(QMouseEvent *e) override {
    setFocus();
    down = last = e->position();
    dragging = true;
    if (tool != "pan")
      player.pause();
  }
  void mouseMoveEvent(QMouseEvent *e) override {
    if (dragging && tool == "pan") {
      pan += e->position() - last;
      last = e->position();
      update();
    }
  }
  void mouseReleaseEvent(QMouseEvent *e) override {
    if (!dragging)
      return;
    dragging = false;
    if (tool != "pan" && !locked)
      annotate(down, tool == "arrow" ? e->position() : down);
  }
  void keyPressEvent(QKeyEvent *e) override {
    if (e->key() == Qt::Key_N && !locked) {
      player.pause();
      annotate(imageRect().center(), imageRect().center());
    } else if (e->key() == Qt::Key_0)
      fit();
    else
      QWidget::keyPressEvent(e);
  }
  void annotate(QPointF start, QPointF end) {
    auto r = imageRect();
    if (image.isNull() || !r.contains(start) || !r.contains(end))
      return;
    // A modal note editor runs an event loop. Freeze the displayed evidence
    // before it opens so playback cannot change the attached frame or time.
    player.pause();
    const auto annotatedFrame = image;
    const auto annotatedTime = frameTime;
    bool accepted = false;
    auto text = QInputDialog::getMultiLineText(
        this, "Evidence note",
        "Describe what the agent should preserve or change:", {}, &accepted);
    if (!accepted || text.trimmed().isEmpty())
      return;
    QJsonObject a{{"media", mediaId},
                  {"text", text.trimmed()},
                  {"x", (start.x() - r.x()) / r.width()},
                  {"y", (start.y() - r.y()) / r.height()},
                  {"end_x", (end.x() - r.x()) / r.width()},
                  {"end_y", (end.y() - r.y()) / r.height()},
                  {"time_ms", kind == "clip" ? annotatedTime : 0}};
    marks.append(a);
    update();
    if (onMark)
      onMark(a, annotatedFrame);
  }
};
class Desk final : public QMainWindow {
public:
  QJsonObject config, manifest, draft;
  QString bundleId, caseId, store, reviewedManifestHash;
  bool changing = false, history = false, fixture = false;
  QListWidget *queue, *cases, *mediaList, *notes;
  QLabel *title, *subtitle, *caseTitle, *context, *summary, *delivery,
      *timeLabel, *beforeCaption, *afterCaption;
  QPushButton *approve, *reject, *play, *caseApprove, *caseChanges, *retry;
  QPlainTextEdit *caseNote, *generalNote;
  QCheckBox *compare;
  Canvas *before, *after;
  QWidget *beforePanel;
  QSlider *scrub;
  QFileSystemWatcher watcher;
  QProcess process;
  QString pendingCommand;
  explicit Desk(QJsonObject conf, QString purpose, bool testFixture)
      : config(std::move(conf)), fixture(testFixture) {
    store = config["store"].toString();
    setWindowTitle("Factory Proof Desk" +
                   (purpose.isEmpty() ? QString() : " — " + purpose));
    resize(1580, 970);
    setMinimumSize(1080, 720);
    auto *root = new QWidget;
    auto *outer = new QVBoxLayout(root);
    outer->setContentsMargins(0, 0, 0, 0);
    outer->setSpacing(0);
    setCentralWidget(root);
    auto *banner = new QWidget;
    banner->setObjectName("banner");
    auto *top = new QHBoxLayout(banner);
    top->setContentsMargins(24, 16, 24, 16);
    auto *brand = label("FACTORY  /  PROOF DESK", "brand");
    brand->setMinimumWidth(340);
    top->addWidget(brand);
    top->addStretch();
    top->addWidget(label(fixture ? "PASSIVE APPLICATION FIXTURE · SAMPLE DATA"
                                 : "Human visual review",
                         "muted"));
    outer->addWidget(banner);
    auto *split = new QSplitter;
    outer->addWidget(split, 1);
    auto *left = new QWidget;
    left->setObjectName("sidebar");
    auto *ll = new QVBoxLayout(left);
    ll->setContentsMargins(18, 22, 18, 20);
    ll->setSpacing(12);
    ll->addWidget(label("Review queue", "heading"));
    auto *tabs = new QHBoxLayout;
    auto *pending = button("Pending");
    auto *past = button("History");
    auto *refresh = button("↻", "Refresh the queue (F5)");
    tabs->addWidget(pending);
    tabs->addWidget(past);
    tabs->addWidget(refresh);
    ll->addLayout(tabs);
    queue = new QListWidget;
    queue->setAccessibleName("Changes awaiting review");
    queue->setMaximumHeight(190);
    ll->addWidget(queue);
    ll->addWidget(label("REQUIRED EVIDENCE", "eyebrow"));
    cases = new QListWidget;
    cases->setAccessibleName("Required evidence cases and decisions");
    ll->addWidget(cases, 1);
    ll->addWidget(label(
        "Each change is reviewed as a bundle.\nAll required cases must pass.",
        "muted"));
    split->addWidget(left);
    auto *center = new QWidget;
    auto *cl = new QVBoxLayout(center);
    cl->setContentsMargins(24, 18, 24, 18);
    cl->setSpacing(12);
    title = label("Select a proof", "title");
    subtitle = label(
        "The agent's evidence and review requirements appear here.", "muted");
    cl->addWidget(title);
    cl->addWidget(subtitle);
    caseTitle = label("Required evidence", "heading");
    context = label("", "muted");
    cl->addWidget(caseTitle);
    cl->addWidget(context);
    auto *controls = new QHBoxLayout;
    compare = new QCheckBox("Before / after");
    compare->setChecked(true);
    controls->addWidget(compare);
    controls->addStretch();
    auto *tools = new QButtonGroup(this);
    int index = 0;
    for (auto name : {"Pan", "Pin", "Arrow"}) {
      auto *b = button(name);
      b->setCheckable(true);
      if (index++ == 0)
        b->setChecked(true);
      tools->addButton(b);
      controls->addWidget(b);
      connect(b, &QPushButton::clicked, this, [this, name] {
        before->tool = after->tool = QString(name).toLower();
      });
    }
    auto *fit = button("Fit", "Fit both views (0)");
    controls->addWidget(fit);
    cl->addLayout(controls);
    auto *pictures = new QHBoxLayout;
    beforePanel = new QWidget;
    auto *afterPanel = new QWidget;
    auto *bcol = new QVBoxLayout(beforePanel);
    auto *acol = new QVBoxLayout(afterPanel);
    bcol->setContentsMargins(0, 0, 0, 0);
    acol->setContentsMargins(0, 0, 0, 0);
    beforeCaption = label("BEFORE", "eyebrow");
    afterCaption = label("AFTER · CANDIDATE", "eyebrow");
    before = new Canvas;
    after = new Canvas;
    bcol->addWidget(beforeCaption);
    bcol->addWidget(before, 1);
    acol->addWidget(afterCaption);
    acol->addWidget(after, 1);
    pictures->addWidget(beforePanel, 1);
    pictures->addWidget(afterPanel, 1);
    cl->addLayout(pictures, 1);
    auto *timeline = new QHBoxLayout;
    play = button("▶", "Play or pause candidate clip (Space)");
    timeLabel = label("00:00.000 / 00:00.000", "muted");
    scrub = new QSlider(Qt::Horizontal);
    scrub->setAccessibleName("Candidate clip position");
    timeline->addWidget(play);
    timeline->addWidget(timeLabel);
    timeline->addWidget(scrub, 1);
    cl->addLayout(timeline);
    cl->addWidget(label("EVIDENCE FOR THIS CASE", "eyebrow"));
    mediaList = new QListWidget;
    mediaList->setMaximumHeight(110);
    mediaList->setAccessibleName(
        "Candidate images and clips; select one to review");
    cl->addWidget(mediaList);
    split->addWidget(center);
    auto *right = new QWidget;
    right->setObjectName("feedback");
    auto *rl = new QVBoxLayout(right);
    rl->setContentsMargins(22, 22, 22, 18);
    rl->setSpacing(12);
    auto *feedbackHeader = new QHBoxLayout;
    feedbackHeader->addWidget(label("Feedback", "heading"), 1);
    auto *removeNote =
        button("×", "Remove the selected draft annotation (Delete)");
    removeNote->setAccessibleName("Remove selected annotation");
    removeNote->setMaximumWidth(40);
    feedbackHeader->addWidget(removeNote);
    rl->addLayout(feedbackHeader);
    notes = new QListWidget;
    notes->setWordWrap(true);
    notes->setTextElideMode(Qt::ElideNone);
    notes->setResizeMode(QListView::Adjust);
    notes->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    notes->setMinimumHeight(100);
    notes->setAccessibleName(
        "Pinned notes; activate to seek to the annotated frame");
    rl->addWidget(notes, 1);
    caseNote = new QPlainTextEdit;
    caseNote->setPlaceholderText("Notes for this evidence case…");
    caseNote->setAccessibleName("Case feedback");
    caseNote->setMaximumHeight(140);
    rl->addWidget(caseNote);
    rl->addWidget(label("CASE DECISION", "eyebrow"));
    caseApprove = button("Mark this case approved");
    caseChanges = button("Needs changes");
    rl->addWidget(caseApprove);
    rl->addWidget(caseChanges);
    generalNote = new QPlainTextEdit;
    generalNote->setPlaceholderText("Overall feedback for the change…");
    generalNote->setAccessibleName("Overall review feedback");
    generalNote->setMaximumHeight(100);
    rl->addWidget(generalNote);
    rl->addWidget(
        label("Notes stay in your draft until you send. The agent receives "
              "your decision, notes and marked media together.",
              "muted"));
    delivery = label("Agent waiting", "delivery");
    rl->addWidget(delivery);
    retry = button("Retry saved delivery",
                   "Retry only a definitely unsent decision; uncertain "
                   "deliveries are never duplicated automatically");
    rl->addWidget(retry);
    connect(retry, &QPushButton::clicked, this, [this] {
      if (!fixture && decided() && process.state() == QProcess::NotRunning)
        bridge("deliver", {});
    });
    split->addWidget(right);
    split->setSizes({260, 980, 340});
    split->setStretchFactor(1, 1);
    auto *footer = new QWidget;
    footer->setObjectName("footer");
    auto *fl = new QHBoxLayout(footer);
    fl->setContentsMargins(24, 15, 24, 15);
    summary = label("No proof selected", "muted");
    fl->addWidget(summary, 1);
    reject = button("Send change request");
    approve = button("Approve change");
    approve->setObjectName("primary");
    fl->addWidget(reject);
    fl->addWidget(approve);
    outer->addWidget(footer);
    connect(refresh, &QPushButton::clicked, this, [this] { refreshQueue(); });
    connect(pending, &QPushButton::clicked, this, [this] {
      history = false;
      refreshQueue();
    });
    connect(past, &QPushButton::clicked, this, [this] {
      history = true;
      refreshQueue();
    });
    connect(queue, &QListWidget::currentItemChanged, this,
            [this](QListWidgetItem *item) {
              if (item)
                loadBundle(item->data(Qt::UserRole).toString());
            });
    connect(cases, &QListWidget::currentItemChanged, this,
            [this](QListWidgetItem *item) {
              if (item)
                loadCase(item->data(Qt::UserRole).toString());
            });
    connect(mediaList, &QListWidget::currentRowChanged, this, [this](int row) {
      if (row >= 0)
        loadMedia(row);
    });
    connect(compare, &QCheckBox::toggled, this,
            [this] { loadMedia(mediaList->currentRow()); });
    connect(fit, &QPushButton::clicked, this, [this] {
      before->fit();
      after->fit();
    });
    connect(caseNote, &QPlainTextEdit::textChanged, this, [this] {
      if (!changing && !bundleId.isEmpty()) {
        auto c = review();
        c["note"] = caseNote->toPlainText();
        setReview(c);
      }
    });
    connect(generalNote, &QPlainTextEdit::textChanged, this, [this] {
      if (!changing && !bundleId.isEmpty()) {
        draft["note"] = generalNote->toPlainText();
        saveDraft();
        updateDecision();
      }
    });
    connect(caseApprove, &QPushButton::clicked, this, [this] {
      auto c = review();
      c["status"] = "approved";
      setReview(c);
    });
    connect(caseChanges, &QPushButton::clicked, this, [this] {
      if (caseNote->toPlainText().trimmed().isEmpty() &&
          review()["annotations"].toArray().isEmpty()) {
        caseNote->setFocus();
        caseNote->setPlaceholderText(
            "Describe what needs changing before sending.");
      }
      auto c = review();
      c["status"] = "changes_requested";
      setReview(c);
    });
    auto onMark = [this](const QJsonObject &annotation, const QImage &frame) {
      auto a = annotation;
      auto name = QUuid::createUuid().toString(QUuid::Id128) + ".png";
      auto folder = store + "/" + bundleId + "/draft-frames";
      QDir().mkpath(folder);
      if (!frame.save(folder + "/" + name)) {
        QMessageBox::warning(this, "Frame could not be saved",
                             "The annotation was not saved. Try again after "
                             "checking free space.");
        loadMedia(mediaList->currentRow());
        return;
      }
      a["frame"] = folder + "/" + name;
      auto c = review();
      auto marks = c["annotations"].toArray();
      marks.append(a);
      c["annotations"] = marks;
      setReview(c);
      refreshNotes();
    };
    before->onMark = after->onMark = onMark;
    before->onReady = after->onReady = [this] { updateDecision(); };
    connect(removeNote, &QPushButton::clicked, this, [this] {
      if (decided())
        return;
      int row = notes->currentRow();
      if (row < 0)
        return;
      auto c = review();
      auto marks = c["annotations"].toArray();
      marks.removeAt(row);
      c["annotations"] = marks;
      setReview(c);
      loadMedia(mediaList->currentRow());
      refreshNotes();
    });
    auto *deleteNoteShortcut =
        new QShortcut(QKeySequence(Qt::Key_Delete), notes);
    connect(deleteNoteShortcut, &QShortcut::activated, removeNote,
            &QPushButton::click);
    connect(notes, &QListWidget::itemActivated, this,
            [this](QListWidgetItem *item) {
              auto a = item->data(Qt::UserRole).toJsonObject();
              auto media = caseObject()["media"].toArray();
              for (int i = 0; i < media.size(); ++i)
                if (media[i].toObject()["id"] == a["media"]) {
                  mediaList->setCurrentRow(i);
                  after->player.setPosition(a["time_ms"].toInteger());
                  after->player.pause();
                }
            });
    connect(play, &QPushButton::clicked, this, [this] {
      if (after->player.playbackState() == QMediaPlayer::PlayingState) {
        after->player.pause();
        before->player.pause();
      } else {
        after->player.play();
        if (before->kind == "clip")
          before->player.play();
      }
    });
    after->onPosition = [this](qint64 p, qint64 d) {
      if (!scrub->isSliderDown()) {
        QSignalBlocker block(scrub);
        scrub->setRange(0, int(d));
        scrub->setValue(int(p));
      }
      timeLabel->setText(timestamp(p) + " / " + timestamp(d));
    };
    connect(scrub, &QSlider::sliderMoved, this, [this](int p) {
      after->player.pause();
      after->player.setPosition(p);
      if (before->kind == "clip") {
        before->player.pause();
        before->player.setPosition(p);
      }
    });
    connect(approve, &QPushButton::clicked, this, [this] { send("approved"); });
    connect(reject, &QPushButton::clicked, this,
            [this] { send("changes_requested"); });
    connect(&watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
      if (process.state() == QProcess::NotRunning)
        refreshQueue();
    });
    watcher.addPath(store);
    connect(
        &process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
        this, [this](int code, QProcess::ExitStatus status) {
          auto output = QString::fromUtf8(process.readAllStandardOutput()) +
                        QString::fromUtf8(process.readAllStandardError());
          if (code != 0 || status != QProcess::NormalExit) {
            delivery->setText("Saved locally; delivery needs attention");
            QMessageBox::warning(this, "Review delivery", output.left(6000));
            updateDecision();
            return;
          }
          if (pendingCommand == "decide") {
            bridge("deliver", {});
            return;
          }
          delivery->setText("Delivered to the originating agent");
          refreshQueue();
        });
    connect(&process, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError) {
              delivery->setText("Bridge unavailable; review remains saved");
              QMessageBox::warning(this, "Proof bridge", process.errorString());
            });
    new QShortcut(QKeySequence(Qt::Key_F5), this, [this] { refreshQueue(); });
    new QShortcut(QKeySequence(Qt::Key_Space), this, [this] {
      if (!caseNote->hasFocus() && !generalNote->hasFocus())
        play->click();
    });
    applyStyle();
    refreshQueue();
    updateDecision();
  }
  QString directory() const { return store + "/" + bundleId; }
  bool decided() const {
    return QFileInfo::exists(directory() + "/decision.json");
  }
  QJsonObject caseObject() const {
    for (auto c : manifest["cases"].toArray())
      if (c.toObject()["id"].toString() == caseId)
        return c.toObject();
    return {};
  }
  QJsonObject review() const {
    return draft["cases"].toObject()[caseId].toObject();
  }
  void saveDraft() {
    if (!bundleId.isEmpty() && !decided())
      try {
        saveObject(directory() + "/draft.json", draft);
      } catch (const std::exception &e) {
        delivery->setText(e.what());
      }
  }
  void setReview(const QJsonObject &c) {
    auto reviews = draft["cases"].toObject();
    reviews[caseId] = c;
    draft["cases"] = reviews;
    saveDraft();
    updateDecision();
  }
  void refreshQueue() {
    if (changing)
      return;
    auto selected = bundleId;
    QSignalBlocker block(queue);
    queue->clear();
    QDir dir(store);
    auto folders =
        dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Time);
    QSet<QString> superseded;
    for (const auto &folder : folders) {
      if (QFileInfo::exists(folder.absoluteFilePath() + "/manifest.json"))
        try {
          auto m = readObject(folder.absoluteFilePath() + "/manifest.json");
          if (m.contains("previous"))
            superseded.insert(m["previous"].toString());
        } catch (const std::exception &) {
        }
    }
    for (const auto &folder : folders) {
      if (folder.fileName().startsWith('.'))
        continue;
      auto path = folder.absoluteFilePath();
      // Submission publishes immutable media before Beads/goal registration.
      // Watch the bundle too, so its later registered marker is not missed.
      if (!watcher.directories().contains(path))
        watcher.addPath(path);
      if (!QFileInfo::exists(path + "/manifest.json") ||
          !QFileInfo::exists(path + "/registered.json"))
        continue;
      if (!history && superseded.contains(folder.fileName()))
        continue;
      try {
        auto m = readObject(path + "/manifest.json");
        bool done = QFileInfo::exists(path + "/decision.json");
        if (done != history)
          continue;
        auto *item = new QListWidgetItem(
            m["title"].toString() + "\n" +
            (m["stage"] == "direction" ? "Early direction" : "Final proof") +
            " · " + QString::number(m["cases"].toArray().size()) + " cases");
        item->setData(Qt::UserRole, folder.fileName());
        item->setToolTip(m["bead"].toString() + "\n" +
                         m["revision"].toString());
        queue->addItem(item);
        if (folder.fileName() == selected)
          queue->setCurrentItem(item);
      } catch (const std::exception &) {
      }
    }
    if (queue->currentRow() < 0 && queue->count() > 0)
      queue->setCurrentRow(0);
    queue->setFixedHeight(qBound(65, queue->count() * 72, 200));
    if (auto *item = queue->currentItem()) {
      if (item->data(Qt::UserRole).toString() != bundleId)
        loadBundle(item->data(Qt::UserRole).toString());
    } else if (!selected.isEmpty() && decided()) {
      delivery->setText("Review sent. Open History to revisit it.");
      updateDecision();
    }
  }
  void loadBundle(const QString &id) {
    saveDraft();
    changing = true;
    try {
      bundleId = id;
      manifest = readObject(directory() + "/manifest.json");
      reviewedManifestHash = hashFile(directory() + "/manifest.json");
      draft = QFileInfo::exists(directory() + "/decision.json")
                  ? readObject(directory() + "/decision.json")
              : QFileInfo::exists(directory() + "/draft.json")
                  ? readObject(directory() + "/draft.json")
                  : QJsonObject{{"cases", QJsonObject{}},
                                {"note", ""},
                                {"attachments", QJsonArray{}}};
      auto reviews = draft["cases"].toObject();
      for (auto value : manifest["cases"].toArray()) {
        auto c = value.toObject();
        auto key = c["id"].toString();
        if (!reviews.contains(key))
          reviews[key] = QJsonObject{{"status", "unreviewed"},
                                     {"note", ""},
                                     {"annotations", QJsonArray{}}};
      }
      draft["cases"] = reviews;
      title->setText(manifest["title"].toString() + "  ·  " +
                     (manifest["stage"] == "direction" ? "Early direction"
                                                       : "Final proof"));
      subtitle->setText(manifest["bead"].toString() + " · Candidate " +
                        manifest["revision"].toString().left(12) + " · " +
                        manifest["actor"].toString());
      generalNote->setPlainText(draft["note"].toString());
      cases->clear();
      for (auto value : manifest["cases"].toArray()) {
        auto c = value.toObject();
        auto *item = new QListWidgetItem(c["title"].toString());
        item->setData(Qt::UserRole, c["id"].toString());
        cases->addItem(item);
      }
      changing = false;
      if (cases->count()) {
        cases->setCurrentRow(0);
        loadCase(cases->item(0)->data(Qt::UserRole).toString());
      }
      delivery->setText(decided() ? "Decision saved" : "Agent waiting");
      if (QFileInfo::exists(directory() + "/delivery.json"))
        delivery->setText(
            "Delivery: " +
            readObject(directory() + "/delivery.json")["status"].toString());
      updateDecision();
    } catch (const std::exception &e) {
      changing = false;
      QMessageBox::warning(this, "Cannot open proof", e.what());
    }
  }
  void loadCase(const QString &id) {
    if (changing)
      return;
    changing = true;
    caseId = id;
    auto c = caseObject();
    bool hasBaseline = false;
    for (auto value : c["media"].toArray())
      hasBaseline |= value.toObject()["role"] == "before";
    compare->setVisible(hasBaseline);
    caseTitle->setText(c["title"].toString());
    context->setText(c["criteria"].toString() + "\n" + c["context"].toString());
    caseNote->setPlainText(review()["note"].toString());
    mediaList->clear();
    int selected = 0, index = 0;
    for (auto value : c["media"].toArray()) {
      auto media = value.toObject();
      mediaList->addItem((media["kind"] == "clip" ? "▶  " : "▧  ") +
                         media["caption"].toString() + " · " +
                         media["role"].toString());
      if (media["role"] != "before")
        selected = index;
      ++index;
    }
    changing = false;
    mediaList->setCurrentRow(selected);
    loadMedia(selected);
    refreshNotes();
    updateDecision();
  }
  void loadMedia(int index) {
    if (changing || index < 0)
      return;
    auto all = caseObject()["media"].toArray();
    if (index >= all.size())
      return;
    auto media = all[index].toObject();
    auto marks = review()["annotations"].toArray();
    after->load(directory() + "/" + media["path"].toString(), media, marks);
    afterCaption->setText(media["role"] == "concept" ? "CONCEPT · NOT GAMEPLAY"
                          : media["role"] == "before" ? "BEFORE"
                                                      : "AFTER · CANDIDATE");
    bool hasBefore = false;
    if (compare->isChecked() && media["role"] != "before")
      for (auto value : all) {
        auto candidate = value.toObject();
        if (candidate["role"] == "before") {
          before->load(directory() + "/" + candidate["path"].toString(),
                       candidate, marks);
          hasBefore = true;
          break;
        }
      }
    before->setVisible(hasBefore);
    beforeCaption->setVisible(hasBefore);
    beforePanel->setVisible(hasBefore);
    if (!hasBefore)
      before->player.stop();
    play->setEnabled(media["kind"] == "clip");
    scrub->setEnabled(media["kind"] == "clip");
    updateDecision();
  }
  void refreshNotes() {
    notes->clear();
    int n = 0;
    for (auto value : review()["annotations"].toArray()) {
      auto a = value.toObject();
      auto *item = new QListWidgetItem(QString::number(++n) + " · " +
                                       timestamp(a["time_ms"].toInteger()) +
                                       "\n" + a["text"].toString());
      item->setData(Qt::UserRole, a);
      item->setToolTip(
          "<qt>" + a["text"].toString().toHtmlEscaped().replace("\n", "<br>") +
          "</qt>");
      item->setData(Qt::AccessibleDescriptionRole, a["text"].toString());
      notes->addItem(item);
    }
  }
  void updateDecision() {
    int passed = 0, changes = 0;
    auto reviews = draft["cases"].toObject();
    for (int i = 0; i < cases->count(); ++i) {
      auto *item = cases->item(i);
      auto key = item->data(Qt::UserRole).toString();
      auto status = reviews[key].toObject()["status"].toString();
      QString name;
      for (auto c : manifest["cases"].toArray())
        if (c.toObject()["id"] == key)
          name = c.toObject()["title"].toString();
      if (status == "approved")
        ++passed;
      if (status == "changes_requested")
        ++changes;
      item->setText(name + "\n" +
                    (status == "approved"            ? "Approved"
                     : status == "changes_requested" ? "Needs changes"
                                                     : "Not reviewed"));
      item->setForeground(QColor(status == "approved"            ? "#8ed4b3"
                                 : status == "changes_requested" ? "#ffbd7b"
                                                                 : "#dce6f4"));
    }
    int total = manifest["cases"].toArray().size();
    summary->setText(QString("%1 approved / %2 need changes / %3 not reviewed")
                         .arg(passed)
                         .arg(changes)
                         .arg(total - passed - changes));
    bool active = !bundleId.isEmpty() && !decided() &&
                  process.state() == QProcess::NotRunning;
    approve->setText(manifest["stage"] == "direction" ? "Approve direction"
                                                      : "Approve change");
    approve->setEnabled(active && total > 0 && passed == total);
    reject->setEnabled(
        active &&
        (changes > 0 || !draft["note"].toString().trimmed().isEmpty()));
    caseApprove->setEnabled(active && after->error.isEmpty() &&
                            !after->image.isNull());
    caseChanges->setEnabled(active);
    caseNote->setReadOnly(!active);
    generalNote->setReadOnly(!active);
    before->locked = after->locked = !active;
    bool needsDelivery = decided();
    try {
      if (QFileInfo::exists(directory() + "/delivery.json"))
        needsDelivery =
            readObject(directory() + "/delivery.json")["status"] != "delivered";
    } catch (const std::exception &) {
    }
    retry->setVisible(needsDelivery);
    retry->setEnabled(needsDelivery &&
                      process.state() == QProcess::NotRunning && !fixture);
  }
  void send(const QString &verdict) {
    if (fixture) {
      QMessageBox::information(this, "Sample fixture",
                               "This is isolated sample data. It cannot "
                               "approve work or contact an agent.");
      return;
    }
    try {
      saveDraft();
      auto decision = draft;
      decision["verdict"] = verdict;
      decision["reviewed_manifest_sha256"] = reviewedManifestHash;
      auto reviews = decision["cases"].toObject();
      for (auto it = reviews.begin(); it != reviews.end(); ++it) {
        auto c = it.value().toObject();
        if (c["status"] == "changes_requested" &&
            c["note"].toString().trimmed().isEmpty()) {
          QString combined;
          for (auto a : c["annotations"].toArray())
            combined += a.toObject()["text"].toString() + "\n";
          c["note"] = combined;
          it.value() = c;
        }
      }
      decision["cases"] = reviews;
      QJsonArray paths;
      auto folder = directory() + "/marked-frames";
      QDir().mkpath(folder);
      for (auto it = reviews.begin(); it != reviews.end(); ++it) {
        auto marks = it.value().toObject()["annotations"].toArray();
        for (auto value : marks) {
          auto a = value.toObject();
          QImage frame(a["frame"].toString());
          if (frame.isNull())
            throw std::runtime_error("An annotated frame is missing; restore "
                                     "it or remove that annotation");
          QJsonArray sameMedia;
          for (auto other : marks)
            if (other.toObject()["media"] == a["media"])
              sameMedia.append(other);
          QPainter painter(&frame);
          annotations(painter, QRectF(QPointF(), frame.size()), sameMedia,
                      a["time_ms"].toInteger(), true);
          painter.end();
          auto name = folder + "/" +
                      QUuid::createUuid().toString(QUuid::Id128) + ".png";
          if (!frame.save(name))
            throw std::runtime_error("Cannot save marked feedback image");
          paths.append(wslPath(name));
        }
      }
      decision["attachments"] = paths;
      auto path = directory() + "/human-decision-request.json";
      saveObject(path, decision);
      bridge("decide", {"--decision", wslPath(path)});
    } catch (const std::exception &e) {
      QMessageBox::warning(this, "Cannot submit review", e.what());
    }
  }
  void bridge(const QString &command, const QStringList &extra) {
    pendingCommand = command;
    QStringList args{"--distribution",
                     config["distro"].toString(),
                     "--exec",
                     config["bridge"].toString(),
                     command,
                     "--root",
                     config["root"].toString(),
                     "--id",
                     bundleId};
    args += extra;
    delivery->setText(command == "decide" ? "Saving human decision…"
                                          : "Delivering feedback…");
    process.start("wsl.exe", args);
    updateDecision();
  }
  void applyStyle() {
    qApp->setStyle(QStyleFactory::create("Fusion"));
    qApp->setFont(QFont("Segoe UI", 10));
    qApp->setStyleSheet(R"(
        QWidget {background:#101720;color:#dde4ef;font-size:15px;} #banner,#sidebar {background:#18222f;} #feedback {background:#192430;} #footer {background:#192635;}
        QLabel {background:transparent;} #brand {font-size:21px;font-weight:700;} #title {font-size:25px;font-weight:700;} #heading {font-size:20px;font-weight:600;}
        #eyebrow {color:#91a9c2;font-size:12px;font-weight:600;} #muted {color:#a4b7cd;} #delivery {color:#f0c68d; padding:8px;background:#3c362c;border-radius:6px;}
        QPushButton {background:#293647;border:1px solid #34475a;border-radius:6px;padding:9px 12px;font-weight:600;}
        QPushButton:hover {background:#344c65;} QPushButton:checked {background:#304c67;border-color:#8cbef5;} QPushButton:focus {border:2px solid #91c2ff;}
        QPushButton:disabled {color:#637286;background:#222e3c;} #primary {background:#74b3ff;color:#102137;} #primary:disabled {background:#29313c;color:#647082;}
        QListWidget {border:none;background:transparent;outline:none;} QListWidget::item {padding:12px 8px;border-radius:6px;margin-bottom:5px;} QListWidget::item:selected {background:#29405a;}
        QPlainTextEdit {background:#101a25;border:1px solid #34475a;border-radius:6px;padding:8px;} QPlainTextEdit:focus {border-color:#91c2ff;}
        QSplitter::handle {background:#2a3b4c;width:1px;} QSlider::groove:horizontal {height:5px;background:#52687f;} QSlider::handle:horizontal {background:#aad2ff;width:14px;margin:-5px 0;border-radius:7px;}
        QScrollBar:vertical {background:#182330;width:10px;} QScrollBar::handle:vertical {background:#425872;min-height:25px;} QToolTip {background:#263b50;color:#eff5ff;border:1px solid #7196bd;padding:7px;}
    )");
  }
};
} // namespace
int main(int argc, char **argv) {
  QApplication app(argc, argv);
  QCoreApplication::setApplicationName("Factory Proof Desk");
  QCoreApplication::setOrganizationName("Factory");
  QCommandLineParser parser;
  parser.addHelpOption();
  parser.addOption({"config", "Configuration JSON", "path"});
  parser.addOption(
      {"test-purpose", "Concise purpose shown in the window title", "text"});
  parser.addOption({"fixture", "Isolated sample proof store"});
  parser.addOption({"capture", "Save a passive screenshot then exit", "path"});
  parser.addOption({"case", "Select a fixture evidence case", "id"});
  parser.addOption({"viewport", "Fixture client size WIDTHxHEIGHT", "size"});
  parser.addOption({"self-test",
                    "Run passive fixture UI/media checks and write JSON",
                    "path"});
  parser.process(app);
  try {
    auto path = parser.value("config");
    if (path.isEmpty())
      path = qEnvironmentVariable("LOCALAPPDATA") +
             "/FactoryProofDesk/config.json";
    if ((parser.isSet("fixture") || parser.isSet("capture")) &&
        parser.value("test-purpose").trimmed().isEmpty())
      throw std::runtime_error(
          "Agent fixture/capture launches require --test-purpose");
    Desk desk(readObject(path), parser.value("test-purpose"),
              parser.isSet("fixture"));
    if ((parser.isSet("case") || parser.isSet("viewport") ||
         parser.isSet("self-test")) &&
        !parser.isSet("fixture"))
      throw std::runtime_error(
          "Fixture controls require an isolated --fixture launch");
    if (parser.isSet("viewport")) {
      auto size = parser.value("viewport").split('x');
      if (size.size() != 2)
        throw std::runtime_error("Expected WIDTHxHEIGHT");
      desk.resize(size[0].toInt(), size[1].toInt());
    }
    desk.show();
    if (parser.isSet("case")) {
      for (int i = 0; i < desk.cases->count(); ++i)
        if (desk.cases->item(i)->data(Qt::UserRole).toString() ==
            parser.value("case"))
          desk.cases->setCurrentRow(i);
    }
    if (parser.isSet("self-test")) {
      auto state = std::make_shared<QJsonObject>();
      (*state)["desktop_input"] = false;
      auto probe = desk.store + "/watcher-probe";
      if (QFileInfo::exists(probe))
        throw std::runtime_error(
            "Previous fixture probe must be inspected before rerunning");
      QTimer::singleShot(300, &desk, [&, state] {
        (*state)["partial_bundle_blocks_approval"] = !desk.approve->isEnabled();
        (*state)["case_count"] = desk.cases->count();
        (*state)["image_loaded"] =
            !desk.after->image.isNull() || desk.after->kind == "clip";
        if (desk.after->kind == "clip")
          desk.after->player.play();
      });
      QTimer::singleShot(350, &desk, [&, probe] {
        QDir().mkpath(probe);
        auto manifest = desk.manifest;
        manifest["id"] = "watcher-probe";
        manifest["title"] = "Registration watcher fixture";
        saveObject(probe + "/manifest.json", manifest);
      });
      QTimer::singleShot(1000, &desk, [probe] {
        saveObject(probe + "/registered.json",
                   QJsonObject{{"registered", true}});
      });
      QTimer::singleShot(1800, &desk, [&, state] {
        if (desk.after->kind == "clip") {
          (*state)["clip_advanced"] = desk.after->frameTime > 500;
          desk.after->player.pause();
          desk.after->player.setPosition(1200);
        } else
          (*state)["clip_advanced"] = true;
      });
      QTimer::singleShot(2800, &desk, [&, state, probe] {
        bool observed = false;
        for (int i = 0; i < desk.queue->count(); ++i)
          observed |=
              desk.queue->item(i)->data(Qt::UserRole) == "watcher-probe";
        (*state)["late_registration_detected"] = observed;
        QDir(probe).removeRecursively();
        desk.refreshQueue();
        (*state)["media_error_free"] =
            desk.after->error.isEmpty() && !desk.after->image.isNull();
        (*state)["clip_seek"] = desk.after->kind != "clip" ||
                                std::abs(desk.after->frameTime - 1200) < 150;
        auto controls = desk.findChildren<QPushButton *>();
        bool bounds = true;
        for (auto *b : controls)
          if (b->isVisible() && !desk.rect().contains(QRect(
                                    b->mapTo(&desk, QPoint()), b->size())))
            bounds = false;
        (*state)["controls_in_client"] = bounds;
        (*state)["single_media_fills_area"] =
            desk.beforePanel->isVisible() ||
            desk.after->width() >
                desk.after->parentWidget()->parentWidget()->width() * .8;
        QJsonObject mark{
            {"media", desk.after->mediaId},
            {"text", "Passive fixture: confirm this motion frame."},
            {"x", .45},
            {"y", .4},
            {"end_x", .65},
            {"end_y", .5},
            {"time_ms", desk.after->frameTime}};
        desk.after->onMark(mark, desk.after->image);
        const auto savedMark =
            desk.review()["annotations"].toArray().last().toObject();
        QImage stored(savedMark["frame"].toString());
        desk.after->marks.append(mark);
        (*state)["annotation_frame_saved"] =
            !stored.isNull() && savedMark["time_ms"] == mark["time_ms"] &&
            desk.after->markedFrame() != desk.after->image;
        desk.after->zoom = 2.;
        desk.after->pan = {20, 15};
        auto zoomed = desk.after->imageRect();
        desk.after->fit();
        (*state)["zoom_and_fit"] =
            zoomed.width() > desk.after->imageRect().width();
        bool passed = true;
        for (auto key :
             {"partial_bundle_blocks_approval", "image_loaded", "clip_advanced",
              "media_error_free", "clip_seek", "controls_in_client",
              "zoom_and_fit", "single_media_fills_area",
              "annotation_frame_saved", "late_registration_detected"})
          passed &= (*state)[key].toBool();
        (*state)["status"] = passed ? "pass" : "fail";
        saveObject(parser.value("self-test"), *state);
        if (parser.isSet("capture") &&
            !desk.grab().save(parser.value("capture")))
          passed = false;
        app.exit(passed ? 0 : 1);
      });
    }
    if (parser.isSet("capture") && !parser.isSet("self-test"))
      QTimer::singleShot(2000, &desk, [&] {
        if (!desk.grab().save(parser.value("capture")))
          app.exit(2);
        else
          app.quit();
      });
    return app.exec();
  } catch (const std::exception &e) {
    QMessageBox::critical(nullptr, "Factory Proof Desk", e.what());
    return 1;
  }
}
