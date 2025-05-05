# Azure Synapse Pipeline – Trigger Power BI Dataset Refresh

This repository contains the JSON definition of an Azure Synapse pipeline that securely triggers a **Power BI semantic model (dataset) refresh** using **Managed Identity** and the **Power BI REST API**.

## 📄 Pipeline File

- `PowerBI-Dataset-Refresh.json`: Full Synapse pipeline definition including:
  - Web activity to trigger the refresh
  - Loop using an Until activity to monitor refresh status
  - Switch activity to handle success/failure logic

## 📘 Full Tutorial

For a detailed step-by-step walkthrough on how to configure permissions, create the pipeline, and monitor the refresh status, check out the full blog post on Medium:

👉 [How to Trigger a Power BI Semantic Model Refresh from a Synapse Pipeline](https://medium.com/@barbaramalafaia/how-to-trigger-a-power-bi-semantic-model-refresh-from-a-synapse-pipeline-xxxxxx)  
_(Replace the Medium URL above once published)_

## 🛠️ Technologies Used

- Azure Synapse Pipelines
- Azure Managed Identity
- Power BI REST API
- Azure AD Security Groups
- PowerShell (for permissions setup)

## ✅ Prerequisites

To use this pipeline, ensure that:

- The Synapse workspace has Managed Identity enabled.
- The Managed Identity is added to a **cloud-based** Azure AD security group.
- Power BI tenant settings allow service principal API access.
- The Managed Identity is granted access to the Power BI workspace.
- You replace all required parameters (Workspace ID, Dataset ID, etc.) in the pipeline.

## 🙋‍♀️ Author

Barbara Malafaia  
Data Engineer | Microsoft Data Platform Enthusiast  
📍 Originally from Minas Gerais, Brazil 🇧🇷 | Living in Australia since 2022 🇦🇺  
🔗 [LinkedIn](https://www.linkedin.com/in/barbaramalafaia) | [Medium](https://medium.com/@barbaramalafaia)
