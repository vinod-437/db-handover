import os

path = r"c:\Office_Work\Project2021\GitHub_Project_AG\db-handover\dashboard.html"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

target = """                    </a>\n                </div>\n            </div>\n\n            <!-- Salary Generation -->"""

replacement = """                    </a>\n                    <a href="./attendnaceapproval/uspsavebulkattendance_business_drilldown_flowchart.html" class="file-link">\n                        <i class="fa-regular fa-file-code"></i>\n                        <span>Approval Drill-Down Flowchart</span>\n                        <i class="fa-solid fa-chevron-right"></i>\n                    </a>\n                </div>\n            </div>\n\n            <!-- Salary Generation -->"""

new_content = content.replace(target, replacement)
# Fallback for CRLF if needed
target_crlf = """                    </a>\r\n                </div>\r\n            </div>\r\n\r\n            <!-- Salary Generation -->"""
replacement_crlf = """                    </a>\r\n                    <a href="./attendnaceapproval/uspsavebulkattendance_business_drilldown_flowchart.html" class="file-link">\r\n                        <i class="fa-regular fa-file-code"></i>\r\n                        <span>Approval Drill-Down Flowchart</span>\r\n                        <i class="fa-solid fa-chevron-right"></i>\r\n                    </a>\r\n                </div>\r\n            </div>\r\n\r\n            <!-- Salary Generation -->"""
new_content = new_content.replace(target_crlf, replacement_crlf)

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
print("Done")
