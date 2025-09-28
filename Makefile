# MacScreenCapture Makefile
# 提供简化的命令来管理项目构建、测试和发布

# 项目配置
PROJECT_NAME = MacScreenCapture
SCHEME_NAME = MacScreenCapture
CONFIGURATION_DEBUG = Debug
CONFIGURATION_RELEASE = Release
BUILD_DIR = build
DERIVED_DATA_PATH = ~/Library/Developer/Xcode/DerivedData

# 添加用户 gem 路径到 PATH
export PATH := $(HOME)/.gem/ruby/2.6.0/bin:$(PATH)

# 颜色输出
BLUE = \033[0;34m
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m # No Color

# 默认目标
.DEFAULT_GOAL := help

# 帮助信息
.PHONY: help
help: ## 显示帮助信息
	@echo "$(BLUE)MacScreenCapture 项目管理$(NC)"
	@echo ""
	@echo "$(GREEN)可用命令:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(GREEN)示例:$(NC)"
	@echo "  make build          # 构建 Debug 版本"
	@echo "  make release        # 构建 Release 版本并打包"
	@echo "  make publish v=1.0.0 # 发布版本 1.0.0"

# 清理构建缓存
.PHONY: clean
clean: ## 清理构建缓存和临时文件
	@echo "$(BLUE)[INFO]$(NC) 清理构建缓存..."
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DERIVED_DATA_PATH)/$(PROJECT_NAME)-*
	@xcodebuild clean -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME_NAME) -configuration $(CONFIGURATION_DEBUG) > /dev/null 2>&1 || true
	@xcodebuild clean -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME_NAME) -configuration $(CONFIGURATION_RELEASE) > /dev/null 2>&1 || true
	@echo "$(GREEN)[SUCCESS]$(NC) 构建缓存已清理"

# 检查环境
.PHONY: check
check: ## 检查开发环境
	@echo "$(BLUE)[INFO]$(NC) 检查开发环境..."
	@which xcodebuild > /dev/null || (echo "$(RED)[ERROR]$(NC) Xcode 命令行工具未安装" && exit 1)
	@xcodebuild -version | head -n 1
	@which git > /dev/null || (echo "$(RED)[ERROR]$(NC) Git 未安装" && exit 1)
	@git --version
	@echo "$(GREEN)[SUCCESS]$(NC) 开发环境检查通过"

# 构建 Debug 版本
.PHONY: build
build: check ## 构建 Debug 版本
	@echo "$(BLUE)[INFO]$(NC) 构建 Debug 版本..."
	@xcodebuild build \
		-project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME_NAME) \
		-configuration $(CONFIGURATION_DEBUG) \
		-destination "generic/platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		| xcpretty || true
	@echo "$(GREEN)[SUCCESS]$(NC) Debug 版本构建完成"

# 构建 Release 版本
.PHONY: build-release
build-release: check ## 构建 Release 版本
	@echo "$(BLUE)[INFO]$(NC) 构建 Release 版本..."
	@mkdir -p $(BUILD_DIR)
	@xcodebuild archive \
		-project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME_NAME) \
		-configuration $(CONFIGURATION_RELEASE) \
		-archivePath $(BUILD_DIR)/$(PROJECT_NAME).xcarchive \
		-destination "generic/platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		| xcpretty || true
	@echo "$(GREEN)[SUCCESS]$(NC) Release 版本构建完成"

# 导出应用程序
.PHONY: export
export: build-release ## 导出应用程序
	@echo "$(BLUE)[INFO]$(NC) 导出应用程序..."
	@mkdir -p $(BUILD_DIR)/export
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(BUILD_DIR)/ExportOptions.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '<plist version="1.0">' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '<dict>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <key>method</key>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <string>development</string>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <key>uploadBitcode</key>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <false/>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <key>uploadSymbols</key>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <false/>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <key>compileBitcode</key>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <false/>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <key>signingStyle</key>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '    <string>automatic</string>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '</dict>' >> $(BUILD_DIR)/ExportOptions.plist
	@echo '</plist>' >> $(BUILD_DIR)/ExportOptions.plist
	@xcodebuild -exportArchive \
		-archivePath $(BUILD_DIR)/$(PROJECT_NAME).xcarchive \
		-exportPath $(BUILD_DIR)/export \
		-exportOptionsPlist $(BUILD_DIR)/ExportOptions.plist \
		| xcpretty || true
	@echo "$(GREEN)[SUCCESS]$(NC) 应用程序导出完成"

# 创建分发包
.PHONY: package
package: export ## 创建分发包 (ZIP 和 DMG)
	@echo "$(BLUE)[INFO]$(NC) 创建分发包..."
	@cd $(BUILD_DIR)/export && \
		VERSION=$$(defaults read "$(PROJECT_NAME).app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0") && \
		ZIP_NAME="$(PROJECT_NAME)-v$$VERSION-macOS.zip" && \
		zip -r "../$$ZIP_NAME" "$(PROJECT_NAME).app" && \
		echo "$(GREEN)[SUCCESS]$(NC) 已创建 ZIP: $(BUILD_DIR)/$$ZIP_NAME"
	@cd $(BUILD_DIR)/export && \
		VERSION=$$(defaults read "$(PROJECT_NAME).app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0") && \
		DMG_NAME="$(PROJECT_NAME)-v$$VERSION-macOS.dmg" && \
		hdiutil create -volname "$(PROJECT_NAME)" -srcfolder "$(PROJECT_NAME).app" -ov -format UDZO "../$$DMG_NAME" && \
		echo "$(GREEN)[SUCCESS]$(NC) 已创建 DMG: $(BUILD_DIR)/$$DMG_NAME" || \
		echo "$(YELLOW)[WARNING]$(NC) DMG 创建失败，但 ZIP 包已创建"

# 完整的 Release 构建流程
.PHONY: release
release: clean package ## 完整的 Release 构建流程 (清理 + 构建 + 打包)
	@echo "$(GREEN)[SUCCESS]$(NC) Release 构建流程完成！"
	@echo "$(BLUE)[INFO]$(NC) 构建产物:"
	@ls -la $(BUILD_DIR)/*.{zip,dmg} 2>/dev/null || true

# 运行应用程序
.PHONY: run
run: build ## 构建并运行应用程序
	@echo "$(BLUE)[INFO]$(NC) 启动应用程序..."
	@APP_PATH=$$(find $(DERIVED_DATA_PATH) -name "$(PROJECT_NAME).app" -path "*/Debug/*" | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			open "$$APP_PATH"; \
			echo "$(GREEN)[SUCCESS]$(NC) 应用程序已启动"; \
		else \
			echo "$(RED)[ERROR]$(NC) 未找到应用程序，请先运行 make build"; \
		fi

# 测试构建
.PHONY: test
test: ## 运行测试 (如果有)
	@echo "$(BLUE)[INFO]$(NC) 运行测试..."
	@xcodebuild test \
		-project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME_NAME) \
		-destination "platform=macOS" \
		| xcpretty || echo "$(YELLOW)[WARNING]$(NC) 没有配置测试或测试失败"

# Git 状态检查
.PHONY: git-status
git-status: ## 检查 Git 状态
	@echo "$(BLUE)[INFO]$(NC) Git 状态:"
	@git status --porcelain | head -10
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "$(YELLOW)[WARNING]$(NC) 有未提交的更改"; \
	else \
		echo "$(GREEN)[SUCCESS]$(NC) 工作目录干净"; \
	fi

# 版本信息
.PHONY: version
version: ## 显示当前版本信息
	@echo "$(BLUE)[INFO]$(NC) 版本信息:"
	@if [ -f "$(PROJECT_NAME)/Info.plist" ]; then \
		VERSION=$$(defaults read "$(PROJECT_NAME)/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "未知"); \
		BUILD=$$(defaults read "$(PROJECT_NAME)/Info.plist" CFBundleVersion 2>/dev/null || echo "未知"); \
		echo "  应用版本: $$VERSION"; \
		echo "  构建版本: $$BUILD"; \
	else \
		echo "$(RED)[ERROR]$(NC) 未找到 Info.plist 文件"; \
	fi
	@LATEST_TAG=$$(git describe --tags --abbrev=0 2>/dev/null || echo "无标签"); \
		echo "  Git 标签: $$LATEST_TAG"

# 更新版本号
.PHONY: bump-version
bump-version: ## 更新版本号 (使用: make bump-version v=1.0.0)
	@if [ -z "$(v)" ]; then \
		echo "$(RED)[ERROR]$(NC) 请指定版本号: make bump-version v=1.0.0"; \
		exit 1; \
	fi
	@echo "$(BLUE)[INFO]$(NC) 更新版本号到 $(v)..."
	@if [ -f "$(PROJECT_NAME)/Info.plist" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(v)" $(PROJECT_NAME)/Info.plist 2>/dev/null || true; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(v)" $(PROJECT_NAME)/Info.plist 2>/dev/null || true; \
		echo "$(GREEN)[SUCCESS]$(NC) 版本号已更新到 $(v)"; \
	else \
		echo "$(RED)[ERROR]$(NC) 未找到 Info.plist 文件"; \
	fi

# 发布版本 (使用脚本)
.PHONY: publish
publish: ## 发布新版本 (使用: make publish v=1.0.0)
	@if [ -z "$(v)" ]; then \
		echo "$(RED)[ERROR]$(NC) 请指定版本号: make publish v=1.0.0"; \
		exit 1; \
	fi
	@echo "$(BLUE)[INFO]$(NC) 发布版本 $(v)..."
	@if [ -f "scripts/release.sh" ]; then \
		./scripts/release.sh --build --push $(v); \
	else \
		echo "$(RED)[ERROR]$(NC) 未找到发布脚本 scripts/release.sh"; \
	fi

# 本地发布测试
.PHONY: publish-test
publish-test: ## 本地发布测试 (使用: make publish-test v=1.0.0)
	@if [ -z "$(v)" ]; then \
		echo "$(RED)[ERROR]$(NC) 请指定版本号: make publish-test v=1.0.0"; \
		exit 1; \
	fi
	@echo "$(BLUE)[INFO]$(NC) 本地发布测试 $(v)..."
	@if [ -f "scripts/release.sh" ]; then \
		./scripts/release.sh --dry-run --build $(v); \
	else \
		echo "$(RED)[ERROR]$(NC) 未找到发布脚本 scripts/release.sh"; \
	fi

# 安装依赖 (如果需要)
.PHONY: install
install: ## 安装项目依赖
	@echo "$(BLUE)[INFO]$(NC) 检查并安装依赖..."
	@which xcpretty > /dev/null || (echo "$(YELLOW)[INFO]$(NC) 安装 xcpretty..." && gem install --user-install xcpretty) || echo "$(YELLOW)[WARNING]$(NC) xcpretty 安装失败，构建输出将不会美化"
	@echo "$(GREEN)[SUCCESS]$(NC) 依赖检查完成"

# 项目信息
.PHONY: info
info: check version git-status ## 显示项目完整信息
	@echo ""
	@echo "$(BLUE)[INFO]$(NC) 项目信息:"
	@echo "  项目名称: $(PROJECT_NAME)"
	@echo "  构建目录: $(BUILD_DIR)"
	@echo "  配置: Debug=$(CONFIGURATION_DEBUG), Release=$(CONFIGURATION_RELEASE)"

# 快速开发流程
.PHONY: dev
dev: clean build run ## 快速开发流程 (清理 + 构建 + 运行)
	@echo "$(GREEN)[SUCCESS]$(NC) 开发环境就绪！"

# 生产发布流程
.PHONY: prod
prod: ## 生产发布流程 (使用: make prod v=1.0.0)
	@if [ -z "$(v)" ]; then \
		echo "$(RED)[ERROR]$(NC) 请指定版本号: make prod v=1.0.0"; \
		exit 1; \
	fi
	@echo "$(BLUE)[INFO]$(NC) 开始生产发布流程..."
	@$(MAKE) git-status
	@$(MAKE) bump-version v=$(v)
	@$(MAKE) release
	@$(MAKE) publish v=$(v)
	@echo "$(GREEN)[SUCCESS]$(NC) 生产发布流程完成！"