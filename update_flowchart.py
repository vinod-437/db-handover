import os

path = r"c:\Office_Work\Project2021\GitHub_Project_AG\db-handover\Salary-Generation\uspgetincrementdiff_flowchart.html"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

target = """    <div class="container">\n        <h1>uspgetincrementdiff</h1>"""

replacement = """    <div class="container">\n        <div style="margin-bottom: 20px;">\n            <a href="../dashboard.html" style="display: inline-block; padding: 10px 20px; background-color: #3498db; color: white; text-decoration: none; border-radius: 5px; font-weight: bold;">&larr; Back to Dashboard</a>\n        </div>\n        <h1>uspgetincrementdiff</h1>"""

target_crlf = """    <div class="container">\r\n        <h1>uspgetincrementdiff</h1>"""
replacement_crlf = """    <div class="container">\r\n        <div style="margin-bottom: 20px;">\r\n            <a href="../dashboard.html" style="display: inline-block; padding: 10px 20px; background-color: #3498db; color: white; text-decoration: none; border-radius: 5px; font-weight: bold;">&larr; Back to Dashboard</a>\r\n        </div>\r\n        <h1>uspgetincrementdiff</h1>"""

content = content.replace(target, replacement)
content = content.replace(target_crlf, replacement_crlf)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("Done")
