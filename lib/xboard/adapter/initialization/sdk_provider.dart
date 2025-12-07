import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:fl_clash/xboard/infrastructure/http/user_agent_config.dart';
import 'package:fl_clash/xboard/core/core.dart';

part 'sdk_provider.g.dart';

final _logger = FileLogger('sdk_provider');

/// XBoard SDK Provider
/// 
/// 负责SDK的初始化和生命周期管理
/// - 自动域名竞速
/// - 自动加载HTTP配置
/// - 缓存SDK实例
@Riverpod(keepAlive: true)
Future<XBoardSDK> xboardSdk(Ref ref) async {
  try {
    _logger.info('[XBoardSdkProvider] 开始初始化SDK');
    
    // 1. 域名竞速选择最快的URL
    String? fastestUrl;
    if (XBoardConfig.lastRacingResult?.domain != null) {
      fastestUrl = XBoardConfig.lastRacingResult!.domain;
      _logger.info('[XBoardSdkProvider] 使用缓存的竞速结果: $fastestUrl');
    } else {
      _logger.info('[XBoardSdkProvider] 开始域名竞速...');
      fastestUrl = await XBoardConfig.getFastestPanelUrl();
    }
    
    if (fastestUrl == null) {
      throw Exception('域名竞速失败：所有面板域名都无法连接');
    }
    
    _logger.info('[XBoardSdkProvider] 域名竞速完成: $fastestUrl');
    
    // 2. 获取面板类型（通过provider接口）
    final panelType = XBoardConfig.provider.getPanelType();
    if (panelType.isEmpty) {
      throw Exception('无法获取面板类型，请检查配置');
    }
    
    _logger.info('[XBoardSdkProvider] 面板类型: $panelType');
    
    // 3. 根据竞速结果决定是否使用代理
    String? proxyUrl;
    final racingResult = XBoardConfig.lastRacingResult;
    if (racingResult != null && racingResult.useProxy) {
      proxyUrl = racingResult.proxyUrl;
      _logger.info('[XBoardSdkProvider] 使用代理: $proxyUrl');
    } else {
      _logger.info('[XBoardSdkProvider] 使用直连');
    }
    
    // 4. 加载HTTP配置
    _logger.info('[XBoardSdkProvider] 加载HTTP配置...');
    final httpConfig = await _loadHttpConfig();
    _logger.info('[XBoardSdkProvider] HTTP配置加载完成');
    
    // 5. 初始化SDK
    final sdk = XBoardSDK.instance;
    await sdk.initialize(
      fastestUrl,
      panelType: panelType,
      proxyUrl: proxyUrl,
      httpConfig: httpConfig,
    );
    
    _logger.info('[XBoardSdkProvider] SDK初始化成功');
    return sdk;
    
  } catch (e, stackTrace) {
    _logger.error('[XBoardSdkProvider] SDK初始化失败', e, stackTrace);
    rethrow;
  }
}

/// 加载HTTP配置
/// 
/// 从配置文件读取：
/// - User-Agent
/// - 混淆前缀
/// - 证书配置
Future<HttpConfig> _loadHttpConfig() async {
  try {
    // 从配置文件获取加密 UA（用于 API 请求和 Caddy 认证）
    final userAgent = await UserAgentConfig.get(
      UserAgentScenario.apiEncrypted,
    );
    
    // 从配置文件获取混淆前缀
    final obfuscationPrefix = await ConfigFileLoaderHelper.getObfuscationPrefix();
    
    // 从配置文件获取证书配置
    final certConfig = await ConfigFileLoaderHelper.getCertificateConfig();
    final certPath = certConfig['path'] as String?;
    final certEnabled = certConfig['enabled'] as bool? ?? true;
    
    // 构建 HttpConfig
    return HttpConfig(
      userAgent: userAgent,
      obfuscationPrefix: obfuscationPrefix,
      enableAutoDeobfuscation: obfuscationPrefix != null,
      certificatePath: certEnabled ? certPath : null,
      enableCertificatePinning: certEnabled && certPath != null,
    );
  } catch (e) {
    _logger.error('[XBoardSdkProvider] 加载HTTP配置失败，使用默认配置', e);
    return HttpConfig.defaultConfig();
  }
}
