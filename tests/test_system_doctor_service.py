from company_os.application.system_doctor_service import (
    SystemDoctorService,
)


def test_system_doctor_reports_core_environment():
    findings = SystemDoctorService().get_findings()

    codes = {
        finding.code
        for finding in findings
    }

    assert "PYTHON_OK" in codes
    assert "PLATFORM" in codes

    assert any(
        code.startswith("POWERSHELL_")
        for code in codes
    )

    assert any(
        code.startswith("OLLAMA_")
        for code in codes
    )