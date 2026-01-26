#!/usr/bin/env python3
"""
SMTP Network Diagnostic Tool
Detaylı SMTP bağlantı problemi teşhis aracı
"""

import socket
import ssl
import smtplib
import sys
import time
import subprocess
import os
from datetime import datetime

class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    END = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    print(f"\n{Colors.BOLD}{Colors.CYAN}{'='*70}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.CYAN}{text}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.CYAN}{'='*70}{Colors.END}\n")

def print_success(text):
    print(f"{Colors.GREEN}✓ {text}{Colors.END}")

def print_error(text):
    print(f"{Colors.RED}✗ {text}{Colors.END}")

def print_warning(text):
    print(f"{Colors.YELLOW}⚠ {text}{Colors.END}")

def print_info(text):
    print(f"{Colors.BLUE}ℹ {text}{Colors.END}")

def test_basic_connectivity():
    """Temel internet bağlantısını test et"""
    print_header("1. TEMEL İNTERNET BAĞLANTISI TESTİ")
    
    test_hosts = [
        ("8.8.8.8", "Google DNS"),
        ("1.1.1.1", "Cloudflare DNS"),
        ("208.67.222.222", "OpenDNS")
    ]
    
    reachable = False
    for host, name in test_hosts:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(3)
            result = sock.connect_ex((host, 53))
            sock.close()
            
            if result == 0:
                print_success(f"{name} ({host}) erişilebilir")
                reachable = True
            else:
                print_error(f"{name} ({host}) erişilemez - Hata kodu: {result}")
        except Exception as e:
            print_error(f"{name} ({host}) test hatası: {e}")
    
    return reachable

def test_dns_resolution():
    """DNS çözümleme testi"""
    print_header("2. DNS ÇÖZÜMLEME TESTİ")
    
    smtp_hosts = [
        "smtp.gmail.com",
        "smtp-mail.outlook.com",
        "smtp.office365.com"
    ]
    
    resolved = {}
    for host in smtp_hosts:
        try:
            start_time = time.time()
            ip_addresses = socket.getaddrinfo(host, 587, socket.AF_INET)
            resolution_time = (time.time() - start_time) * 1000
            
            ips = list(set([addr[4][0] for addr in ip_addresses]))
            resolved[host] = ips
            print_success(f"{host} -> {', '.join(ips)} ({resolution_time:.2f}ms)")
        except socket.gaierror as e:
            print_error(f"{host} DNS çözümlenemedi: {e}")
            resolved[host] = None
        except Exception as e:
            print_error(f"{host} DNS hatası: {e}")
            resolved[host] = None
    
    return resolved

def test_port_connectivity(host, port, timeout=10):
    """Port bağlantı testi - detaylı"""
    print_info(f"Port {port} bağlantısı test ediliyor (timeout: {timeout}s)...")
    
    try:
        start_time = time.time()
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        
        print_info(f"  Bağlantı kuruluyor: {host}:{port}")
        result = sock.connect_ex((host, port))
        connect_time = (time.time() - start_time) * 1000
        
        if result == 0:
            print_success(f"  Port {port} AÇIK ({connect_time:.2f}ms)")
            sock.close()
            return True, connect_time
        else:
            error_msg = os.strerror(result) if result < 256 else f"Bilinmeyen hata kodu: {result}"
            print_error(f"  Port {port} KAPALI - Hata: {error_msg}")
            sock.close()
            return False, None
    except socket.timeout:
        print_error(f"  Port {port} TIMEOUT ({timeout}s)")
        return False, None
    except socket.gaierror as e:
        print_error(f"  DNS Hatası: {e}")
        return False, None
    except Exception as e:
        print_error(f"  Bağlantı Hatası: {type(e).__name__}: {e}")
        return False, None

def test_smtp_ports():
    """SMTP portlarını test et"""
    print_header("3. SMTP PORT BAĞLANTI TESTLERİ")
    
    smtp_configs = [
        ("smtp.gmail.com", 587, "STARTTLS"),
        ("smtp.gmail.com", 465, "SSL/TLS"),
        ("smtp.gmail.com", 25, "Plain/STARTTLS"),
    ]
    
    results = {}
    for host, port, protocol in smtp_configs:
        print(f"\n{Colors.BOLD}Testing {host}:{port} ({protocol}){Colors.END}")
        success, latency = test_port_connectivity(host, port, timeout=10)
        results[f"{host}:{port}"] = (success, latency, protocol)
    
    return results

def test_firewall_and_routing():
    """Firewall ve routing kontrolü"""
    print_header("4. FİREWALL VE ROUTING KONTROLÜ")
    
    # Traceroute
    print_info("Traceroute testi yapılıyor (smtp.gmail.com)...")
    try:
        result = subprocess.run(
            ['traceroute', '-m', '10', '-w', '2', 'smtp.gmail.com'],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            print(result.stdout)
        else:
            print_warning("Traceroute çalıştırılamadı")
    except subprocess.TimeoutExpired:
        print_warning("Traceroute timeout (30s)")
    except FileNotFoundError:
        print_warning("traceroute komutu bulunamadı (apt install traceroute)")
    except Exception as e:
        print_warning(f"Traceroute hatası: {e}")
    
    # iptables kontrolü
    print_info("\nFirewall kuralları kontrol ediliyor...")
    try:
        result = subprocess.run(
            ['sudo', 'iptables', '-L', 'OUTPUT', '-n', '-v'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            output = result.stdout
            if '587' in output or '465' in output or '25' in output:
                print_warning("SMTP portlarıyla ilgili firewall kuralları bulundu:")
                for line in output.split('\n'):
                    if '587' in line or '465' in line or '25' in line:
                        print(f"  {line}")
            else:
                print_success("SMTP portları için özel firewall kuralı yok")
        else:
            print_warning("iptables kontrol edilemedi (sudo gerekli)")
    except Exception as e:
        print_warning(f"Firewall kontrol hatası: {e}")

def test_proxy_settings():
    """Proxy ayarlarını kontrol et"""
    print_header("5. PROXY AYARLARI KONTROLÜ")
    
    proxy_vars = ['http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'no_proxy', 'NO_PROXY']
    proxy_found = False
    
    for var in proxy_vars:
        value = os.environ.get(var)
        if value:
            print_warning(f"{var} = {value}")
            proxy_found = True
    
    if not proxy_found:
        print_success("Sistem proxy ayarı bulunamadı")
    else:
        print_warning("Proxy ayarları bulundu - SMTP bağlantısını engelleyebilir!")
    
    # /etc/environment kontrolü
    try:
        with open('/etc/environment', 'r') as f:
            content = f.read()
            if 'proxy' in content.lower():
                print_warning("/etc/environment dosyasında proxy ayarı var:")
                for line in content.split('\n'):
                    if 'proxy' in line.lower():
                        print(f"  {line}")
    except:
        pass

def test_ssl_tls():
    """SSL/TLS bağlantı testi"""
    print_header("6. SSL/TLS BAĞLANTI TESTİ")
    
    host = "smtp.gmail.com"
    port = 465
    
    print_info(f"SSL/TLS bağlantısı test ediliyor: {host}:{port}")
    
    try:
        context = ssl.create_default_context()
        
        with socket.create_connection((host, port), timeout=10) as sock:
            print_success("TCP bağlantısı kuruldu")
            
            with context.wrap_socket(sock, server_hostname=host) as ssock:
                print_success("SSL/TLS handshake başarılı")
                
                cert = ssock.getpeercert()
                print_success(f"Sertifika konusu: {cert.get('subject')}")
                print_success(f"Sertifika süresi: {cert.get('notAfter')}")
                
                cipher = ssock.cipher()
                print_info(f"Cipher: {cipher[0]}, Protokol: {cipher[1]}")
                
                return True
    except socket.timeout:
        print_error("SSL/TLS bağlantısı TIMEOUT")
        return False
    except ssl.SSLError as e:
        print_error(f"SSL Hatası: {e}")
        return False
    except Exception as e:
        print_error(f"SSL/TLS Hatası: {type(e).__name__}: {e}")
        return False

def test_smtp_handshake(host, port, use_ssl=False, use_starttls=False):
    """SMTP handshake testi - çok detaylı"""
    print_header(f"7. SMTP HANDSHAKE TESTİ ({host}:{port})")
    
    protocol = "SSL" if use_ssl else ("STARTTLS" if use_starttls else "Plain")
    print_info(f"Protokol: {protocol}")
    
    try:
        if use_ssl:
            print_info("SSL bağlantısı kuruluyor...")
            server = smtplib.SMTP_SSL(host, port, timeout=15)
        else:
            print_info("TCP bağlantısı kuruluyor...")
            server = smtplib.SMTP(host, port, timeout=15)
        
        server.set_debuglevel(2)  # Tüm SMTP komutlarını göster
        
        print_success("SMTP sunucusuna bağlanıldı")
        
        if use_starttls:
            print_info("STARTTLS başlatılıyor...")
            server.starttls()
            print_success("STARTTLS başarılı")
        
        print_success("SMTP handshake başarılı!")
        
        server.quit()
        return True
        
    except socket.timeout:
        print_error(f"SMTP bağlantısı TIMEOUT (15s)")
        return False
    except smtplib.SMTPConnectError as e:
        print_error(f"SMTP Bağlantı Hatası: {e}")
        return False
    except smtplib.SMTPServerDisconnected as e:
        print_error(f"Sunucu bağlantıyı kesti: {e}")
        return False
    except Exception as e:
        print_error(f"SMTP Hatası: {type(e).__name__}: {e}")
        import traceback
        print_error(f"Detaylı hata:\n{traceback.format_exc()}")
        return False

def test_smtp_auth():
    """SMTP authentication testi"""
    print_header("8. SMTP AUTHENTICATION TESTİ (OPSİYONEL)")
    
    test_auth = input(f"\n{Colors.YELLOW}Gmail kimlik doğrulama testi yapmak ister misiniz? (y/n): {Colors.END}").lower()
    
    if test_auth != 'y':
        print_info("Authentication testi atlandı")
        return
    
    email = input("Gmail adresiniz: ")
    password = input("Gmail App Password: ")
    
    try:
        print_info("SMTP_SSL ile bağlanılıyor...")
        server = smtplib.SMTP_SSL('smtp.gmail.com', 465, timeout=15)
        server.set_debuglevel(1)
        
        print_info("Login deneniyor...")
        server.login(email, password)
        
        print_success("Authentication BAŞARILI!")
        server.quit()
        return True
        
    except smtplib.SMTPAuthenticationError as e:
        print_error(f"Authentication BAŞARISIZ: {e}")
        print_warning("Gmail App Password'ü kontrol edin")
        return False
    except Exception as e:
        print_error(f"Authentication Hatası: {e}")
        return False

def check_network_interfaces():
    """Network interface bilgilerini göster"""
    print_header("9. NETWORK INTERFACE BİLGİLERİ")
    
    try:
        result = subprocess.run(['ip', 'addr', 'show'], capture_output=True, text=True)
        print(result.stdout)
    except:
        try:
            result = subprocess.run(['ifconfig'], capture_output=True, text=True)
            print(result.stdout)
        except:
            print_warning("Network interface bilgisi alınamadı")
    
    # Default route
    print_info("\nDefault Gateway:")
    try:
        result = subprocess.run(['ip', 'route', 'show', 'default'], capture_output=True, text=True)
        print(result.stdout)
    except:
        print_warning("Default route bilgisi alınamadı")

def generate_report(results):
    """Özet rapor oluştur"""
    print_header("ÖZET RAPOR VE ÖNERİLER")
    
    print(f"{Colors.BOLD}Tarih/Saat:{Colors.END} {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{Colors.BOLD}Host:{Colors.END} {socket.gethostname()}\n")
    
    # Temel sorunları tespit et
    issues = []
    recommendations = []
    
    print(f"{Colors.BOLD}Tespit Edilen Sorunlar:{Colors.END}")
    
    # Proxy kontrolü
    proxy_vars = ['http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY']
    if any(os.environ.get(var) for var in proxy_vars):
        issue = "Corporate proxy ayarları bulundu"
        issues.append(issue)
        print_warning(f"  • {issue}")
        recommendations.append("Proxy bypass ayarı yapın veya SMTP için relay kullanın")
    
    # Port erişim kontrolü
    if not any('smtp.gmail.com:587' in str(k) and v[0] for k, v in results.get('ports', {}).items()):
        issue = "SMTP portlarına erişim yok"
        issues.append(issue)
        print_warning(f"  • {issue}")
        recommendations.append("Firewall kurallarını kontrol edin")
        recommendations.append("IT departmanından SMTP portlarının açılmasını isteyin")
    
    if not issues:
        print_success("  Kritik sorun tespit edilmedi")
    
    print(f"\n{Colors.BOLD}Öneriler:{Colors.END}")
    if recommendations:
        for i, rec in enumerate(recommendations, 1):
            print(f"  {i}. {rec}")
    else:
        print_success("  SMTP bağlantısı çalışıyor olmalı")
    
    # Alternatif çözümler
    print(f"\n{Colors.BOLD}Alternatif Çözümler:{Colors.END}")
    print("  1. Local Postfix relay kullanın (sunucu üzerinde)")
    print("  2. ElastAlert'i host network modunda çalıştırın")
    print("  3. Internal SMTP sunucusu kullanın")
    print("  4. Webhook/Slack gibi alternatif alert yöntemleri")

def main():
    print(f"{Colors.BOLD}{Colors.CYAN}")
    print("""
╔═══════════════════════════════════════════════════════════════════╗
║          SMTP Network Diagnostic Tool v1.0                        ║
║          Detaylı Network ve SMTP Teşhis Aracı                     ║
╚═══════════════════════════════════════════════════════════════════╝
    """)
    print(Colors.END)
    
    results = {}
    
    try:
        # Testleri sırayla çalıştır
        results['internet'] = test_basic_connectivity()
        time.sleep(1)
        
        results['dns'] = test_dns_resolution()
        time.sleep(1)
        
        results['ports'] = test_smtp_ports()
        time.sleep(1)
        
        test_firewall_and_routing()
        time.sleep(1)
        
        test_proxy_settings()
        time.sleep(1)
        
        results['ssl'] = test_ssl_tls()
        time.sleep(1)
        
        # SMTP handshake testleri
        print("\n" + "="*70)
        test_smtp_handshake("smtp.gmail.com", 587, use_starttls=True)
        time.sleep(1)
        
        print("\n" + "="*70)
        test_smtp_handshake("smtp.gmail.com", 465, use_ssl=True)
        time.sleep(1)
        
        test_smtp_auth()
        time.sleep(1)
        
        check_network_interfaces()
        
        # Özet rapor
        generate_report(results)
        
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}Test kullanıcı tarafından durduruldu{Colors.END}")
        sys.exit(1)
    except Exception as e:
        print_error(f"Beklenmeyen hata: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()