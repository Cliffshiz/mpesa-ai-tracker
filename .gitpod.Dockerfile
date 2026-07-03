FROM gitpod/workspace-full

USER gitpod

RUN cd /home/gitpod && \
    git clone https://github.com/flutter/flutter.git -b stable --depth 1

ENV PATH="/home/gitpod/flutter/bin:${PATH}"

RUN mkdir -p /home/gitpod/android-sdk/cmdline-tools && \
    cd /home/gitpod/android-sdk/cmdline-tools && \
    curl -o cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
    unzip -q cmdline-tools.zip && \
    mv cmdline-tools latest && \
    rm cmdline-tools.zip

ENV ANDROID_HOME="/home/gitpod/android-sdk"
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true
RUN sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

RUN flutter precache
RUN flutter doctor
